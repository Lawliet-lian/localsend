import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/conversation_receive_card_vm.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/conversation/conversation_composer.dart';
import 'package:localsend_app/widget/conversation/conversation_entry_tile.dart';
import 'package:localsend_app/widget/conversation/conversation_list.dart';
import 'package:localsend_app/widget/conversation/conversation_receive_card.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:localsend_app/widget/transfer_security_label.dart';

/// 会话面板：设备列表 + 会话详情的响应式组合（方案 6.1）。
///
/// 布局合同：
/// - 两栏仅当“窗口宽度 >= 800（isDesktop）且本组件自身可用宽度 >= 620”，
///   因为 ResponsiveBuilder 读的是整个窗口而不是内容剩余宽度（方案第 1 节）；
/// - 窗口 700~799 一律单栏；窄屏从列表进入详情，在同一容器内切换（PopScope 返回，不 push 第二套页面）；
/// - 宽度切换时选中状态由调用方 provider 持有（conversationUiProvider），本组件不保存私有选中状态。
///
/// 纯展示 + 文字提交（P4/P6c）+ 接收卡片挂载点（P7c）：本组件自身无接受/拒绝能力，
/// 卡片回调由接线层转发回 serverProvider 原有动作，
/// 传输控制始终归属原有 provider（第 4 节不变量 1）。
class ConversationPanel extends StatelessWidget {
  final bool dropEnabled;
  final Future<void> Function(List<DropItem>)? onDropFiles;
  final List<ConversationPeerView> views;

  /// 全部会话记录；面板按选中设备的 peerKey 过滤展示。
  final List<ConversationEntry> entries;
  final Widget Function(ConversationEntry)? entryBuilder;
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

  /// 附件选择回调（P9b）：透传给 composer；null 时附件按钮不渲染（dumb 合同）。
  final VoidCallback? onPickAttachment;
  final ValueChanged<FilePickerOption>? onPickAttachmentOption;

  /// 附件按钮门槛投影（P9b）：接线层 watch conversationAttachmentEnabledProvider。
  final bool attachmentEnabled;

  /// 选择器打开期间锁住会话发送（P9b，方案 6.3）：接线层传 picking 标志；
  /// 仅禁用发送/附件按钮，草稿保留。设备切换锁由接线层在 onSelect 里自行拦截。
  final bool sendingLocked;

  /// 会话内接收卡片（P7c）：仅当活跃 conversation 接收 session 的对端是
  /// **当前选中设备**时由接线层传入；legacy/无 session 为 null，详情页不渲染。
  final ConversationReceiveCardVm? receiveCard;

  /// 卡片按钮回调：接受（携带勾选固化后的 fileNameMap）/拒绝/取消/关闭，
  /// 全部转发 serverProvider 同名动作；本组件不做任何决策判断。
  final void Function(Map<String, String> fileNameMap)? onReceiveAccept;
  final VoidCallback? onReceiveDecline;
  final VoidCallback? onReceiveCancel;
  final VoidCallback? onReceiveClose;

  /// 清空当前会话（P9a-3）：仅回调携带 peerKey；确认弹窗与 dispatch 由接线层（conversation_tab）负责，
  /// 保持本组件 dumb（不弹对话框、不订阅 provider）。为 null 时顶栏不渲染菜单。
  final void Function(String peerKey)? onClearPeer;

  const ConversationPanel({
    super.key,
    this.dropEnabled = false,
    this.onDropFiles,
    required this.views,
    required this.entries,
    this.entryBuilder,
    required this.selectedPeerKey,
    required this.onSelect,
    required this.draftText,
    required this.onDraftChanged,
    required this.onSendText,
    this.onPickAttachment,
    this.onPickAttachmentOption,
    this.attachmentEnabled = true,
    this.sendingLocked = false,
    this.receiveCard,
    this.onReceiveAccept,
    this.onReceiveDecline,
    this.onReceiveCancel,
    this.onReceiveClose,
    this.onClearPeer,
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
    return _ConversationDropTarget(
      key: ValueKey(selected.peerKey),
      enabled: dropEnabled && checkPlatformIsDesktop(),
      alias: selected.alias,
      onDrop: onDropFiles,
      child: _ConversationDetail(
        view: selected,
        entries: _entriesFor(selected.peerKey),
        entryBuilder: entryBuilder,
        // 两栏时列表常驻左侧无需返回按钮；单栏详情必须能返回列表（方案 6.2）
        showBackButton: !twoPane,
        onBack: () => onSelect(null),
        draftText: draftText,
        onDraftChanged: onDraftChanged,
        onSendText: onSendText,
        onPickAttachment: onPickAttachment,
        onPickAttachmentOption: onPickAttachmentOption,
        attachmentEnabled: attachmentEnabled,
        sendingLocked: sendingLocked,
        // P7c：卡片已在接线层按选中 peer 匹配，这里直接挂载
        receiveCard: receiveCard,
        onReceiveAccept: onReceiveAccept,
        onReceiveDecline: onReceiveDecline,
        onReceiveCancel: onReceiveCancel,
        onReceiveClose: onReceiveClose,
        onClearPeer: onClearPeer,
      ),
    );
  }

  /// 选中设备的记录，按创建时间升序（最新的在气泡区底部）。
  List<ConversationEntry> _entriesFor(String peerKey) {
    final filtered = entries.where((e) => e.peerKey == peerKey).toList();
    filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered;
  }
}

/// 会话详情：顶栏（设备名 + 在线状态）+ 接收卡片（P7c）+ 气泡区 + 输入栏（P6c）。
class _ConversationDetail extends StatelessWidget {
  final ConversationPeerView view;
  final List<ConversationEntry> entries;
  final Widget Function(ConversationEntry)? entryBuilder;
  final bool showBackButton;
  final VoidCallback onBack;
  final String draftText;
  final ValueChanged<String> onDraftChanged;
  final ValueChanged<String> onSendText;
  final VoidCallback? onPickAttachment;
  final ValueChanged<FilePickerOption>? onPickAttachmentOption;
  final bool attachmentEnabled;
  final bool sendingLocked;
  final ConversationReceiveCardVm? receiveCard;
  final void Function(Map<String, String> fileNameMap)? onReceiveAccept;
  final VoidCallback? onReceiveDecline;
  final VoidCallback? onReceiveCancel;
  final VoidCallback? onReceiveClose;

  /// 清空当前会话（P9a-3）：顶栏菜单项点击后回调，携带 view.peerKey。
  final void Function(String peerKey)? onClearPeer;

  const _ConversationDetail({
    required this.view,
    required this.entries,
    required this.entryBuilder,
    required this.showBackButton,
    required this.onBack,
    required this.draftText,
    required this.onDraftChanged,
    required this.onSendText,
    required this.onPickAttachment,
    required this.onPickAttachmentOption,
    required this.attachmentEnabled,
    required this.sendingLocked,
    required this.receiveCard,
    required this.onReceiveAccept,
    required this.onReceiveDecline,
    required this.onReceiveCancel,
    required this.onReceiveClose,
    required this.onClearPeer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = view.device;

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
                // 顶栏右侧菜单（P9a-3）：目前仅「清空当前会话」。点击只回调 onClearPeer(peerKey)，
                // 确认与落盘由接线层完成；只清记录、不删文件、不取消传输（方案第 7 节）。
                if (onClearPeer != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: t.conversation.clearConversation,
                    onSelected: (value) {
                      if (value == 'clear') {
                        onClearPeer!(view.peerKey);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'clear',
                        child: Text(t.conversation.clearConversation),
                      ),
                    ],
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
        // 接收卡片（P7c）：静止在顶栏与气泡区之间；key 按 sessionId 重建，
        // 切 session 时局部勾选状态天然不残留（卡片消失≠取消传输，无任何生命周期动作）
        if (receiveCard != null)
          ConversationReceiveCard(
            key: ValueKey(receiveCard!.sessionId),
            vm: receiveCard!,
            onAccept: (fileNameMap) => onReceiveAccept?.call(fileNameMap),
            onDecline: () => onReceiveDecline?.call(),
            onCancel: () => onReceiveCancel?.call(),
            onClose: () => onReceiveClose?.call(),
          ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    t.conversation.empty,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                )
              : _EntryListView(entries: entries, entryBuilder: entryBuilder),
        ),
        // 输入栏（P6c）：离线设备禁用发送但保留草稿（方案 6.2：离线仍可查看历史、禁发送）；
        // key 按 peerKey 重建，切设备不串输入；
        // P9b：选择器打开期间（sendingLocked）同样禁用发送，草稿不受影响
        if (view.online && device?.ip != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TransferSecurityLabel(encrypted: device!.https),
          ),
        ConversationComposer(
          key: ValueKey(view.peerKey),
          initialValue: draftText,
          enabled: view.online && !sendingLocked,
          onChanged: onDraftChanged,
          onSend: onSendText,
          onPickAttachment: onPickAttachment,
          onPickAttachmentOption: onPickAttachmentOption,
          attachmentEnabled: attachmentEnabled,
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
  final Widget Function(ConversationEntry)? entryBuilder;

  const _EntryListView({required this.entries, required this.entryBuilder});

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
        itemBuilder: (context, index) {
          final entry = entries[entries.length - 1 - index];
          return KeyedSubtree(
            key: ValueKey(entry.entryId),
            child: entryBuilder?.call(entry) ?? ConversationEntryTile(entry: entry),
          );
        },
      ),
    );
  }
}

class _ConversationDropTarget extends StatefulWidget {
  final bool enabled;
  final String alias;
  final Future<void> Function(List<DropItem>)? onDrop;
  final Widget child;
  const _ConversationDropTarget({super.key, required this.enabled, required this.alias, required this.onDrop, required this.child});

  @override
  State<_ConversationDropTarget> createState() => _ConversationDropTargetState();
}

class _ConversationDropTargetState extends State<_ConversationDropTarget> {
  bool hovering = false;
  @override
  void didUpdateWidget(covariant _ConversationDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) hovering = false;
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => hovering = true),
      onDragExited: (_) => setState(() => hovering = false),
      onDragDone: (event) {
        setState(() => hovering = false);
        final drop = widget.onDrop;
        if (drop == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.conversation.offline)));
        } else {
          unawaited(drop(List<DropItem>.of(event.files)));
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (hovering)
            IgnorePointer(
              child: Container(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                alignment: Alignment.center,
                child: Text(t.conversation.dropToSend(name: widget.alias), textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}
