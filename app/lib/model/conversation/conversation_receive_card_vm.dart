import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_isolates/model/session_status.dart';

/// 会话内接收卡片的视图模型（P7c）。
///
/// 视图状态 ≠ 传输状态（方案第 4 节不变量 1）：本对象只是对
/// `serverProvider.session` 的只读投影，按钮回调接线回 serverProvider 原有动作，
/// 卡片自身不拥有任何取消/决策能力。
class ConversationReceiveCardVm {
  final ReceiveSessionState session;

  /// 逐文件实时进度读取（接线自 fileTransferProvider.getProgress，0..1）。
  /// 以函数注入而非直接依赖 provider：投影层可纯 Dart 测试（方案 9.1）。
  final double Function(String fileId) progressOf;

  ConversationReceiveCardVm({
    required this.session,
    required this.progressOf,
  });

  String get sessionId => session.sessionId;

  /// 卡片上的发起方名称：senderAlias 已含"收藏备注优先"语义（onPrepareUpload 决定，与旧接收历史一致）。
  String get senderAlias => session.senderAlias;

  bool get isWaiting => session.status == SessionStatus.waiting;

  bool get isSending => session.status == SessionStatus.sending;

  /// 文字消息请求（P9a-1）：`session.message` 非空即命中"单 text 文件 + preview"协议判定。
  /// 卡片据此切换为文字确认视图（正文 + 接受/拒绝），而非文件勾选列表。
  bool get isMessage => session.message != null;

  /// 文字消息正文（非消息请求为 null）。
  String? get message => session.message;

  /// 发送端在决策/传输期间取消：卡片给出提示与关闭按钮（对应旧 ReceivePage 的同款状态）。
  bool get isCanceledBySender => session.status == SessionStatus.canceledBySender;

  /// 文件总数（消息请求不建卡片，见 [conversationReceiveCardEligible]）。
  int get fileCount => session.files.length;

  /// 会话内接收不弹文件选择页：默认全选作为复用的基础集合。
  Map<String, String> get allFileNameMap => {
    for (final f in session.files.values) f.file.id: f.desiredName ?? f.file.fileName,
  };

  /// 聚合进度（按字节加权，与旧 ProgressPage 的算法一致）：0..1。
  double get totalProgress {
    int totalBytes = 0;
    int currentBytes = 0;
    for (final receivingFile in session.files.values) {
      final size = receivingFile.file.size;
      totalBytes += size;
      currentBytes += (progressOf(receivingFile.file.id) * size).round();
    }
    if (totalBytes <= 0) {
      return 0;
    }
    return currentBytes / totalBytes;
  }
}

/// 判定一个接收 session 是否应显示为会话内卡片（P7c 核心判定，纯函数）。
///
/// 条件全部来自现有事实，不猜全局 UI（与 P7a 判定同原则）：
/// - session 非空且仍活跃（waiting/sending/canceledBySender；终态后 session 很快被清理，不展示残留卡片）；
/// - presentation == conversation（P7a 在 onPrepareUpload 创建时固定；legacy 永远走旧 ReceivePage，会话内无双按钮）。
///
/// 消息请求（`session.message` 非空）同样建卡片（P9a-1 修正）：conversation 模式在 onPrepareUpload
/// 已跳过旧 ReceivePage，若卡片再排除消息，文字确认的接受/拒绝入口就彻底缺失，消息会永远停在
/// waiting、发送端一直等待。故这里不再以 message 作为排除条件。
bool conversationReceiveCardEligible({
  required ReceiveSessionState? session,
  required TransferPresentation presentation,
}) {
  if (session == null || presentation != TransferPresentation.conversation) {
    return false;
  }
  const visibleStatuses = {SessionStatus.waiting, SessionStatus.sending, SessionStatus.canceledBySender};
  return visibleStatuses.contains(session.status);
}

/// 卡片是否应出现在选中设备的详情页：session 对端与当前选中 peer 匹配才展示。
/// （列表角标 hasActiveReceive 负责提醒"有活跃接收"，卡片只属于对转会话的设备。）
bool conversationReceiveCardForPeer({
  required ConversationReceiveCardVm? vm,
  required String? selectedPeerKey,
  required String Function(String fingerprint) peerKeyFor,
}) {
  final session = vm?.session;
  if (session == null || selectedPeerKey == null) {
    return false;
  }
  return peerKeyFor(session.sender.fingerprint) == selectedPeerKey;
}
