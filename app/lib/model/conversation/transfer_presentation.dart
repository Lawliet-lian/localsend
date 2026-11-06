/// 一次传输的展示路径（方案 5.3）。
///
/// 决定该 session 的事件与进度呈现在哪个容器 UI：
/// 旧的独立页面（[legacy]）还是会话气泡（[conversation]）。
///
/// 重要边界：
/// - 它**不进入协议、不进入 isolate**，只存在于 Dart 应用层；
/// - 每个发送 session 单独保存（见 transferPresentationProvider），
///   不得用"当前处于哪个 tab"去猜测正在运行任务的展示模式；
/// - 默认值 [legacy] 保证所有既有调用点行为完全不变。
///
/// 纯内存枚举，不持久化、不被任何 @MappableClass 引用，因此无需 @MappableEnum。
enum TransferPresentation {
  /// 旧流程：SendPage / ProgressPage 等独立页面（改造前的默认行为）
  legacy,

  /// 会话流程：在会话 tab 内以气泡呈现，不跳转旧页面
  conversation,
}

/// 接收侧展示模式判定（方案 P7a / 5.3）。
///
/// 判定条件只来自现有请求路径与设置开关，不猜测全局 UI 状态：
/// - [enabled]：“会话接收展示”开关是否开启（默认关闭；开关 UI 属 P9a）；
/// - [viaWebUpload]：请求是否来自 web 上传页（链接接收）——链接收发永远 legacy（方案 6.1）；
/// - WebRTC 接收走独立路径（webrtc_receiver.dart），根本不会进入本函数，天然隔离。
///
/// 开关关闭时结果恒为 legacy，与改造前行为完全一致（门槛：legacy 接收零变化）。
TransferPresentation decideReceivePresentation({
  required bool enabled,
  required bool viaWebUpload,
}) {
  return enabled && !viaWebUpload ? TransferPresentation.conversation : TransferPresentation.legacy;
}

/// 会话模式下「收藏设备自动接收」判定（双方互收藏才互相免确认）。
///
/// 单向判定：每个接收端只查**自己的收藏列表**是否命中发送方指纹，
/// 协议无需携带「对方是否收藏我」。由此天然得到：
/// - A 收藏 B、B 未收藏 A：B→A 自动接收；A→B 仍需 B 手动同意；
/// - 双方互相收藏：两个方向都自动接收（无障碍）。
///
/// 仅在 [TransferPresentation.conversation] 展示模式生效；legacy、链接接收、
/// WebRTC 走各自路径，不受本判定影响。纯函数，便于单测（与 [decideReceivePresentation] 同原则）。
bool shouldAutoAcceptFavoriteInConversation({
  required TransferPresentation presentation,
  required bool isFavorite,
}) {
  return presentation == TransferPresentation.conversation && isFavorite;
}
