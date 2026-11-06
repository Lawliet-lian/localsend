import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/widget/conversation/conversation_composer.dart';
import 'package:localsend_app/widget/conversation/conversation_entry_tile.dart';
import 'package:localsend_app/widget/conversation/conversation_list.dart';
import 'package:localsend_app/widget/responsive_builder.dart';

/// 会话面板：设备列表 + 会话详情的响应式组合（方案 6.1）。
///
/// 布局合同：
/// - 两栏仅当“窗口宽度 >= 800（isDesktop）且本组件自身可用宽度 >= 620”，
///   因为 ResponsiveBuilder 读的是整个窗口而不是内容剩余宽度（方案第 1 节）；
/// - 窗口 700~799 一律单栏；窄屏从列表进入详情，在同一容器内切换（PopScope 返回，不 push 第二套页面）；
/// - 宽度切换时选中状态由调用方 provider 持有（conversationUiProvider），本组件不保存私有选中状态。
///
/// 纯展示 + 文字提交（P4/P6c）：无接受/拒绝按钮、无取消能力——分别属 P7c/P8，
/// 传输控制始终归属原有 provider（第 4 节不变量 1）。
class ConversationPanel extends StatelessWidget {
  final List<ConversationPeerView> views;

  /// 全部会话记录；面板按选中设备的 peerKey 过滤展示。
  final List<ConversationEntry> entries;
  final String? selectedPeerKey;

  /// 窄屏（单栏）时是否展示详情页。
  /// 接线自 conversationUiProvider 的 showDetailOnMobile：返回列表只收起详情、
  /// 保留选中高亮和草稿；两栏模式不受此参数影响（右列直接跟随选中）。
  final bool showDetailOnNarrow;

  /// 选中设备；传 null 表示返回列表（窄屏单栏时生效）。
  final ValueChanged<String?> onSelect;

  /// 当前选中设备的文字草稿（接线自 conversationUiProvider 的 per-peerKey 草稿）。
  final String draftText;

  /// 草稿变化（接线层按选中 peerKey 写入 conversationUiProvider）。
  final ValueChanged<String> onDraftChanged;

  /// 发送纯文字消息（原文未 trim；接线层发起 conversation 发送，P6c）。
  final ValueChanged<String> onSendText;

  const ConversationPanel({
    super.key,
    required this.views,
    required this.entries,
    required this.selectedPeerKey,
    required this.onSelect,
    required this.draftText,
    required this.onDraftChanged,
    required this.onSendText,
    this.showDetailOnNarrow = true,
  });

  /// 两栏所需的本组件最小可用宽度（方案 6.1：左列约 260 + 右列至少 360）。
  static const double _twoPaneMinWidth = 620;

  /// 左列固定宽度。
  static const double _listPaneWidth = 260;

  ConversationPeerView? get _selectedView {
    final key = selectedPeerKey;
    if (key == null) {
      return null;
    }
    for (final view in views) {
      if (view.peerKey == key) {
        return view;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (sizing) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final twoPane = sizing.isDesktop && constraints.maxWidth >= _twoPaneMinWidth;

            if (twoPane) {
              return Row(
                children: [
                  // 左列固定约 260 逻辑像素（方案 6.1）
                  SizedBox(width: _listPaneWidth, child: _listArea(context)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _detailArea(context, twoPane: true)),
                ],
              );
            }

            // 单栏：未选中或窄屏详情被收起时显示列表；选中且展开时显示详情并用 PopScope 接管系统返回
            final selected = _selectedView;
            if (selected == null || !showDetailOnNarrow) {
              return _listArea(context);
            }
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) {
                  onSelect(null);
                }
              },
              child: _detailArea(context, twoPane: false),
            );
          },
        );
      },
    );
  }

  Widget _listArea(BuildContext context) {
    return ConversationList(
      views: views,
      selectedPeerKey: selectedPeerKey,
      onTap: onSelect,
    );
  }

  Widget _detailArea(BuildContext context, {required bool twoPane}) {
    final selected = _selectedView;
    if (selected == null) {
      // 两栏模式但没有选中设备
      return Center(
        child: Text(
          t.conversation.selectDevice,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return _ConversationDetail(
      view: selected,
      entries: _entriesFor(selected.peerKey),
      // 两栏时列表常驻左侧无需返回按钮；单栏详情必须能返回列表（方案 6.2）
      showBackButton: !twoPane,
      onBack: () => onSelect(null),
      draftText: draftText,
      onDraftChanged: onDraftChanged,
      onSendText: onSendText,
    );
  }

  /// 选中设备的记录，按创建时间升序（最新的在气泡区底部）。
  List<ConversationEntry> _entriesFor(String peerKey) {
    final filtered = entries.where((e) => e.peerKey == peerKey).toList();
    filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered;
  }
}

/// 会话详情：顶栏（设备名 + 在线状态）+ 气泡区 + 输入栏（P6c）。
class _ConversationDetail extends StatelessWidget {
  final ConversationPeerView view;
  final List<ConversationEntry> entries;
  final bool showBackButton;
  final VoidCallback onBack;
  final String draftText;
  final ValueChanged<String> onDraftChanged;
  final ValueChanged<String> onSendText;

  const _ConversationDetail({
    required this.view,
    required this.entries,
    required this.showBackButton,
    required this.onBack,
    required this.draftText,
    required this.onDraftChanged,
    required this.onSendText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶栏：设备名称 + 准确的发现状态（方案 6.2）
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                // 两栏模式下 panel 传 showBackButton: false，单栏时应显示返回按钮
                if (showBackButton) IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
                Icon(view.deviceType.icon, color: view.online ? theme.colorScheme.onSurface : theme.colorScheme.outline),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(view.alias, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                Text(
                  view.online ? t.general.online : t.general.offline,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: view.online ? theme.colorScheme.primary : theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 离线提示：仍可查看历史（发送入口在 P5 依据 view.online 禁用）
        if (!view.online)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              t.conversation.offline,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    t.conversation.empty,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                )
              : _EntryListView(entries: entries),
        ),
        // 输入栏（P6c）：离线设备禁用发送但保留草稿（方案 6.2：离线仍可查看历史、禁发送）；
        // key 按 peerKey 重建，切设备不串输入
        ConversationComposer(
          key: ValueKey(view.peerKey),
          initialValue: draftText,
          enabled: view.online,
          onChanged: onDraftChanged,
          onSend: onSendText,
        ),
      ],
    );
  }
}

/// 气泡区：ListView.builder 惰性构建（方案 6.2，不用一次性 Column）。
///
/// 使用 reverse 锚定最新记录在底部：新内容追加时视口不会被强制跳动，
/// 用户向上浏览旧消息不受影响（自动滚到底的精细规则属于 P6/P7 接入批）。
class _EntryListView extends StatelessWidget {
  final List<ConversationEntry> entries;

  const _EntryListView({required this.entries});

  @override
  Widget build(BuildContext context) {
    // SelectableText 需要 Material 祖先；组件不假设外部一定被 Scaffold 包裹
    return Material(
      type: MaterialType.transparency,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        // index 0 = 最新记录（底部），倒序访问
        itemCount: entries.length,
        itemBuilder: (context, index) => ConversationEntryTile(entry: entries[entries.length - 1 - index]),
      ),
    );
  }
}
