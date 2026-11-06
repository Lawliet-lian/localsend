import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/transfer_presentation_provider.dart';
import 'package:localsend_isolates/model/file_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 接收侧会话记录器（P7b，与发送侧 ConversationSendRecorder 对称）。
///
/// 职责边界：
/// - 只服务于 presentation == conversation 的接收 session（P7a 在 onPrepareUpload 创建时固定）；
///   legacy session 的每一次调用都是空操作，保证旧接收路径**不产生任何会话记录**（双轨隔离）；
/// - 记录只存展示摘要（名称/大小/结果/保存路径），绝不持有 ReceivingFile/FileDto 原对象、
///   bytes、token、PIN、目录句柄等资源引用；
/// - 全部写入按 entryId（direction=receive + localSessionId）upsert，重复事件不追加新气泡；
/// - 终态快照必须在 closeSession 移除 presentation 映射之前形成（remove 之后 guard 会挡掉一切写入），
///   也必须在 fileTransferProvider.removeSession 清进度之前形成；
/// - 旧 receiveHistoryProvider 的行为完全不受本类影响（双轨，各写各的存储）。
class ConversationReceiveRecorder {
  ConversationReceiveRecorder(this._ref);

  final Ref _ref;

  /// 该 session 是否走会话展示模式（未记录 = legacy 默认）
  bool _isConversation(String sessionId) {
    return _ref.read(transferPresentationProvider)[sessionId] == TransferPresentation.conversation;
  }

  /// 接入点 1：onPrepareUpload 创建 ReceiveSessionState 后登记设备信息与文件摘要。
  /// 接收侧没有"校验和计算"阶段，请求一到即是等待用户决定（[ConversationOutcome.waiting]）。
  /// 消息请求（单 text 文件 + preview，协议判定见 ReceiveSessionState.message）登记为
  /// kind = text，正文取 preview 原样（不 trim）；文件摘要置空，与发送侧 P6c 对称。
  void onSessionCreated({
    required ReceiveSessionState session,
  }) {
    if (!_isConversation(session.sessionId)) {
      return;
    }

    final message = session.message;

    _ref
        .redux(conversationProvider)
        .dispatch(
          EnsureTransferEntryAction(
            peer: _peerOf(session),
            direction: ConversationDirection.receive,
            localSessionId: session.sessionId,
            kind: message != null ? ConversationEntryKind.text : ConversationEntryKind.file,
            files: message != null
                ? const []
                : [
                    for (final entry in session.files.entries)
                      ConversationFileSummary(
                        fileId: entry.key,
                        fileName: entry.value.file.fileName,
                        fileType: entry.value.file.fileType,
                        size: entry.value.file.size,
                        outcome: ConversationFileOutcome.pending,
                        path: null,
                        savedToGallery: false,
                        error: null,
                      ),
                  ],
            text: message,
            initialOutcome: ConversationOutcome.waiting,
          ),
        );
  }

  /// 接入点 2：更新阶段/终态；可选整体替换文件摘要与整体错误。
  /// 记录不存在（未登记或已被用户清除）时静默跳过，绝不复活（tombstone 语义由 P2 动作兜底）。
  void update({
    required String sessionId,
    required ConversationOutcome outcome,
    List<ConversationFileSummary>? replaceFiles,
    String? error,
  }) {
    if (!_isConversation(sessionId)) {
      return;
    }

    final entryId = ConversationEntry.buildEntryId(ConversationDirection.receive, sessionId);
    ConversationEntry? entry;
    for (final e in _ref.read(conversationProvider).entries) {
      if (e.entryId == entryId) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      return;
    }

    _ref
        .redux(conversationProvider)
        .dispatch(
          UpsertTransferSnapshotAction(
            entry.copyWith(
              outcome: outcome,
              // 终态盖时间戳；仍在进行中的阶段保持未结束
              finishedAt: outcome.isTerminal ? DateTime.now().toUtc() : null,
              files: replaceFiles ?? entry.files,
              error: error,
            ),
          ),
        );
  }

  /// 接入点 3：用户接受（非消息）。desiredName 为空 = 用户未勾选该文件 → skipped；
  /// 展示文件名改用用户确认的目标名（模型合同：接收侧用 desiredName）。
  void onAccepted({
    required ReceiveSessionState session,
  }) {
    if (!_isConversation(session.sessionId)) {
      return;
    }

    update(
      sessionId: session.sessionId,
      outcome: ConversationOutcome.transferring,
      replaceFiles: [
        for (final entry in session.files.entries)
          ConversationFileSummary(
            fileId: entry.key,
            fileName: entry.value.desiredName ?? entry.value.file.fileName,
            fileType: entry.value.file.fileType,
            size: entry.value.file.size,
            // 无 desiredName = 本端未接受该文件
            outcome: entry.value.desiredName != null ? ConversationFileOutcome.pending : ConversationFileOutcome.skipped,
            path: null,
            savedToGallery: false,
            error: null,
          ),
      ],
    );
  }

  /// 接入点 4：消息请求被确认（空选择 accept，服务器回 204）。
  /// 消息文本在请求到达时就已完整（嵌在 preview 里），确认后即 [ConversationOutcome.finished]。
  void onMessageAccepted({
    required ReceiveSessionState session,
  }) {
    if (session.message == null) {
      // 非消息的空选择不属于"收到消息"终态，交给 closeSession 收口
      return;
    }
    update(sessionId: session.sessionId, outcome: ConversationOutcome.finished);
  }

  /// 接入点 5：全员有结果时的终态快照（finished / partialFailure）。
  /// 每文件结果咨询 fileTransferProvider 的实时状态，路径/相册/单文件错误取
  /// ReceivingFile 的最终值；必须在 closeSession（清进度 + 移除映射）之前调用。
  void onTerminalSnapshot({
    required ReceiveSessionState session,
    required ConversationOutcome outcome,
  }) {
    if (!_isConversation(session.sessionId)) {
      return;
    }

    update(
      sessionId: session.sessionId,
      outcome: outcome,
      replaceFiles: _summariesOf(session),
    );
  }

  /// 接入点 6：closeSession 收口。会话记录仍是非终态（用户在等待/传输中离开页面、
  /// 或取消按钮）时，以 [ConversationOutcome.canceledByReceiver] 收口——本端即接收端，
  /// 语义为"接收被本端中止"；已成终态（accept/decline/取消/全员完成均已先行记录）则不覆盖。
  void onClosing({
    required ReceiveSessionState? session,
  }) {
    if (session == null) {
      return;
    }
    if (!_isConversation(session.sessionId)) {
      return;
    }

    final entryId = ConversationEntry.buildEntryId(ConversationDirection.receive, session.sessionId);
    for (final e in _ref.read(conversationProvider).entries) {
      if (e.entryId == entryId) {
        // 已有终态：quickSave/decline/取消/完成路径均已记录，收口不得覆盖
        if (e.outcome.isTerminal) {
          return;
        }
        break;
      }
    }

    update(
      sessionId: session.sessionId,
      outcome: ConversationOutcome.canceledByReceiver,
      replaceFiles: _summariesOf(session),
    );
  }

  /// 当前会话状态的文件摘要快照（接收方向：带真实保存路径与相册结果）。
  List<ConversationFileSummary> _summariesOf(ReceiveSessionState session) {
    final transferNotifier = _ref.read(fileTransferProvider);
    return [
      for (final entry in session.files.entries)
        ConversationFileSummary(
          fileId: entry.key,
          fileName: entry.value.desiredName ?? entry.value.file.fileName,
          fileType: entry.value.file.fileType,
          size: entry.value.file.size,
          outcome: outcomeFromFileStatus(transferNotifier.getStatus(sessionId: session.sessionId, fileId: entry.key)),
          path: entry.value.path,
          savedToGallery: entry.value.savedToGallery,
          error: entry.value.errorMessage,
        ),
    ];
  }

  /// 对端展示信息：指纹取 session.sender（onPrepareUpload 已用 mTLS 证书指纹替换，可信且不可伪造）；
  /// alias 用 senderAlias（收藏备注名优先于自报名，与旧接收历史一致）。
  static ConversationPeer _peerOf(ReceiveSessionState session) {
    return ConversationPeer(
      peerKey: ConversationPeer.peerKeyFor(session.sender.fingerprint),
      fingerprint: session.sender.fingerprint,
      alias: session.senderAlias,
      deviceType: session.sender.deviceType,
    );
  }

  /// 纯转换：isolate 层的文件实时状态 → 会话记录的展示结果。
  /// queue/sending 尚无最终结果，归为 pending。（与发送侧同款；为保持两个方向
  /// 的文件互相独立，此处不做跨类静态引用。）
  static ConversationFileOutcome outcomeFromFileStatus(FileStatus status) {
    return switch (status) {
      FileStatus.finished => ConversationFileOutcome.success,
      FileStatus.failed => ConversationFileOutcome.failure,
      FileStatus.skipped => ConversationFileOutcome.skipped,
      FileStatus.queue || FileStatus.sending => ConversationFileOutcome.pending,
    };
  }
}
