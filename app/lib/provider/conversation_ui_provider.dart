import 'package:refena_flutter/refena_flutter.dart';

/// 会话 UI 状态：选中设备、窄屏详情显示、按设备的纯文字草稿。
///
/// 严格遵守实施不变量 1/2：本 provider 只保存展示状态，任何方法都不会（也不得）
/// 触发网络取消、拒绝待确认请求或清理传输——选中、返回、缩放窗口与传输层完全无关。
///
/// 草稿按 peerKey 保存（方案 6.3）：绝不使用全局 selectedSendingFilesProvider 充当
/// 每设备文字草稿（它清空时会触发缓存清理）。附件草稿不在第一版范围内。
class ConversationUiState {
  /// 当前选中的会话 peerKey；null 表示未选中任何设备。
  final String? selectedPeerKey;

  /// 窄屏（<800 逻辑像素）是否处于详情页。宽屏两栏布局不读取该标志，
  /// 窗口宽度切换回宽屏时选中设备与草稿保持不变（方案第 2 节核心交付 2）。
  final bool showDetailOnMobile;

  /// peerKey -> 纯文字草稿。内容原样保存：不 trim、不丢失换行（方案 6.2）。
  final Map<String, String> drafts;
  final Set<String> immediateAttachments;

  const ConversationUiState({
    this.selectedPeerKey,
    this.showDetailOnMobile = false,
    this.drafts = const {},
    this.immediateAttachments = const {},
  });
}

/// 会话 UI 状态 provider（普通 UI 状态用 NotifierProvider，方案 5.1）。
final conversationUiProvider = NotifierProvider<ConversationUiService, ConversationUiState>((ref) {
  return ConversationUiService();
});

class ConversationUiService extends Notifier<ConversationUiState> {
  @override
  ConversationUiState init() => const ConversationUiState();

  /// 选中设备并进入详情。切换选中不会拒绝任何待确认请求、不丢任何其他设备的草稿。
  void selectPeer(String peerKey) {
    state = ConversationUiState(
      selectedPeerKey: peerKey,
      showDetailOnMobile: true,
      drafts: state.drafts,
      immediateAttachments: state.immediateAttachments,
    );
  }

  /// 窄屏返回列表：仅收起详情页，保留选中设备（回到宽屏两栏时仍显示同一会话）。
  void backToList() {
    state = ConversationUiState(
      selectedPeerKey: state.selectedPeerKey,
      showDetailOnMobile: false,
      drafts: state.drafts,
      immediateAttachments: state.immediateAttachments,
    );
  }

  /// 更新指定设备的文字草稿。空文本等价于删除草稿（输入框清空不留脏键）。
  void updateDraft(String peerKey, String text) {
    final drafts = Map<String, String>.from(state.drafts);
    if (text.isEmpty) {
      drafts.remove(peerKey);
    } else {
      drafts[peerKey] = text;
    }
    state = ConversationUiState(
      selectedPeerKey: state.selectedPeerKey,
      showDetailOnMobile: state.showDetailOnMobile,
      drafts: drafts,
      immediateAttachments: state.immediateAttachments,
    );
  }

  /// 发送成功后清除该设备草稿；不影响其他设备的草稿。
  void clearDraft(String peerKey) {
    if (!state.drafts.containsKey(peerKey)) {
      return;
    }
    final drafts = Map<String, String>.from(state.drafts)..remove(peerKey);
    state = ConversationUiState(
      selectedPeerKey: state.selectedPeerKey,
      showDetailOnMobile: state.showDetailOnMobile,
      drafts: drafts,
      immediateAttachments: state.immediateAttachments,
    );
  }

  void setImmediateAttachments(String peerKey, bool enabled) {
    final keys = Set<String>.of(state.immediateAttachments);
    if (enabled) {
      keys.add(peerKey);
    } else {
      keys.remove(peerKey);
    }
    state = ConversationUiState(
      selectedPeerKey: state.selectedPeerKey,
      showDetailOnMobile: state.showDetailOnMobile,
      drafts: state.drafts,
      immediateAttachments: keys,
    );
  }
}
