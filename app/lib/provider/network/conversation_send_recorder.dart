import 'dart:convert';

import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/transfer_presentation_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_status.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 发送侧会话记录器（P6b）。
///
/// 职责边界：
/// - 只服务于 presentation == conversation 的 session；legacy session 的每一次调用都是空操作，
///   保证旧发送路径**不产生任何会话记录**（双轨隔离，方案第 8 节 P6b 门槛）；
/// - 记录只存展示摘要（名称/大小/结果），绝不持有 SendingFile/CrossFile 原对象、bytes、token、PIN；
/// - 全部写入按 entryId（direction + localSessionId）upsert，重复事件不追加新气泡（不变量 10）；
/// - 终态快照必须在 closeSession 之前形成——conversation 的 background 语义会在全员成功后
///   直接清理 session，不依赖 finished 状态曾被发布（方案 5.4）。
class ConversationSendRecorder {
  ConversationSendRecorder(this._ref);

  final Ref _ref;

  /// 该 session 是否走会话展示模式（未记录 = legacy 默认）
  bool _isConversation(String sessionId) {
    return _ref.read(transferPresentationProvider)[sessionId] == TransferPresentation.conversation;
  }

  /// 接入点 1：session 创建后登记设备信息与文件摘要，初始阶段 preparing（校验和计算中）。
  /// [selectedFiles] 即 startSession 中已分配 id 的文件列表，id 与后续 FileStatus 的键一致。
  /// [text] 非空表示纯文字会话（P6c）：kind = text，正文原样保存（不 trim、保留换行），
  /// 文件摘要置空列表（协议上消息嵌在单个 text 文件的 preview 里，不占气泡文件行）。
  void onSessionCreated({
    required String sessionId,
    required Device target,
    required List<({String id, CrossFile file})> selectedFiles,
    String? text,
  }) {
    if (!_isConversation(sessionId)) {
      return;
    }

    _ref
        .redux(conversationProvider)
        .dispatch(
          EnsureTransferEntryAction(
            peer: ConversationPeer(
              peerKey: ConversationPeer.peerKeyFor(target.fingerprint),
              fingerprint: target.fingerprint,
              alias: target.alias,
              deviceType: target.deviceType,
            ),
            direction: ConversationDirection.send,
            localSessionId: sessionId,
            kind: text != null ? ConversationEntryKind.text : ConversationEntryKind.file,
            files: text != null
                ? const []
                : [
                    for (final (:id, :file) in selectedFiles)
                      ConversationFileSummary(
                        fileId: id,
                        fileName: file.name,
                        fileType: file.fileType,
                        size: file.size,
                        outcome: ConversationFileOutcome.pending,
                        path: null, // 发送侧没有保存路径
                        savedToGallery: false,
                        error: null,
                      ),
                  ],
            text: text,
            initialOutcome: ConversationOutcome.preparing,
          ),
        );
  }

  /// 接入点 2：更新阶段/终态；可选整体替换文件摘要（接受/跳过/单文件结果）与整体错误。
  /// 记录不存在（未登记或已被用户清除）时静默跳过，绝不复活（tombstone 语义由 P2 动作再兜底）。
  void update({
    required String sessionId,
    required ConversationOutcome outcome,
    List<ConversationFileSummary>? replaceFiles,
    String? error,
  }) {
    if (!_isConversation(sessionId)) {
      return;
    }

    final entryId = ConversationEntry.buildEntryId(ConversationDirection.send, sessionId);
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

  /// 接入点 3：文件进入上传阶段：更新阶段，并把对方未接受（token 为空）的文件标为 skipped。
  void onTransferring({
    required String sessionId,
    required Map<String, SendingFile> files,
  }) {
    if (!_isConversation(sessionId)) {
      return;
    }

    update(
      sessionId: sessionId,
      outcome: ConversationOutcome.transferring,
      replaceFiles: [
        for (final entry in files.entries)
          ConversationFileSummary(
            fileId: entry.key,
            fileName: entry.value.file.fileName,
            fileType: entry.value.file.fileType,
            size: entry.value.file.size,
            // 无 token = 接收端未选择该文件
            outcome: entry.value.token != null ? ConversationFileOutcome.pending : ConversationFileOutcome.skipped,
            path: null,
            savedToGallery: false,
            error: null,
          ),
      ],
    );
  }

  /// 接入点 4：从最终 session 状态形成终态快照（含每个文件的实时结果与单文件错误）。
  /// 必须在 closeSession 之前调用：closeSession 会移除 presentation 映射并清理进度状态。
  void onTerminalSnapshot({
    required SendSessionState session,
    required ConversationOutcome outcome,
  }) {
    if (!_isConversation(session.sessionId)) {
      return;
    }

    final transferNotifier = _ref.read(fileTransferProvider);
    final summaries = [
      for (final entry in session.files.entries)
        ConversationFileSummary(
          fileId: entry.key,
          fileName: entry.value.file.fileName,
          fileType: entry.value.file.fileType,
          size: entry.value.file.size,
          outcome: outcomeFromFileStatus(transferNotifier.getStatus(sessionId: session.sessionId, fileId: entry.key)),
          path: null,
          savedToGallery: false,
          error: entry.value.errorMessage,
        ),
    ];

    update(
      sessionId: session.sessionId,
      outcome: outcome,
      replaceFiles: summaries,
      error: session.errorMessage,
    );
  }

  /// 纯转换：判断本次发送是否为纯文字消息，并提取原文。
  /// 条件与 startSession 内嵌 preview 的协议判断完全一致（单文件 + text + 有 bytes），
  /// 保证“会话里认定为消息”与“协议按消息发送”不会分叉；非消息返回 null（文件会话）。
  static String? extractMessageText(List<CrossFile> files) {
    if (files.length == 1 && files.first.fileType == FileType.text && files.first.bytes != null) {
      // 原样解码：不 trim、不丢失换行（方案 6.2）
      return utf8.decode(files.first.bytes!);
    }
    return null;
  }

  /// 纯转换：isolate 层的文件实时状态 → 会话记录的展示结果。
  /// queue/sending 尚无最终结果，归为 pending。
  static ConversationFileOutcome outcomeFromFileStatus(FileStatus status) {
    return switch (status) {
      FileStatus.finished => ConversationFileOutcome.success,
      FileStatus.failed => ConversationFileOutcome.failure,
      FileStatus.skipped => ConversationFileOutcome.skipped,
      FileStatus.queue || FileStatus.sending => ConversationFileOutcome.pending,
    };
  }
}
