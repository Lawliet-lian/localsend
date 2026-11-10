import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';

/// 会话设备列表（方案 6.1 左栏/窄屏首页）。
///
/// 纯展示组件：数据来自 P3 的 ConversationPeerView 投影，交互只有一个"选中设备"回调；
/// 不含发送、清除等能力（那些属于 P5/P8 接入的 provider 动作）。
class ConversationList extends StatelessWidget {
  final List<ConversationPeerView> views;
  final String? selectedPeerKey;
  final ValueChanged<String> onTap;
  final VoidCallback? onRefresh;
  final bool refreshing;
  final VoidCallback? onCollapse;

  const ConversationList({
    super.key,
    required this.views,
    required this.selectedPeerKey,
    required this.onTap,
    this.onRefresh,
    this.refreshing = false,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget group(String title, bool favorite) {
      final devices = views.where((view) => view.isFavorite == favorite).toList();
      final online = devices.where((view) => view.online).length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ExpansionTile(
            key: PageStorageKey('conversation-group-$favorite'),
            initiallyExpanded: true,
            shape: const Border(),
            collapsedShape: const Border(),
            backgroundColor: colors.surfaceContainerLow,
            collapsedBackgroundColor: colors.surfaceContainerLow,
            dense: true,
            visualDensity: const VisualDensity(vertical: -1),
            tilePadding: const EdgeInsetsDirectional.only(start: 14, end: 12),
            leading: Icon(favorite ? Icons.star_rounded : Icons.radar, size: 20, color: colors.primary),
            title: Row(
              children: [
                Flexible(
                  child: Text(title, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: '${t.general.online}: $online / ${devices.length}',
                  child: Text('$online / ${devices.length}', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                ),
              ],
            ),
            children: [
              for (final view in devices) ...[
                _ConversationListTile(view: view, selected: view.peerKey == selectedPeerKey, onTap: () => onTap(view.peerKey)),
                Divider(height: 1, indent: 16, endIndent: 16, color: colors.outlineVariant.withValues(alpha: 0.45)),
              ],
            ],
          ),
        ),
      );
    }

    final content = ListView(
      children: [
        group(t.conversation.myFavorites, true),
        group(t.sendTab.nearbyDevices, false),
        if (views.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(t.conversation.empty, style: Theme.of(context).textTheme.bodyMedium)),
          ),
      ],
    );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
            child: Row(
              children: [
                Expanded(child: Text(t.conversation.title, style: Theme.of(context).textTheme.titleMedium)),
                if (onRefresh != null)
                  IconButton(
                    tooltip: t.sendTab.scan,
                    onPressed: refreshing ? null : onRefresh,
                    icon: refreshing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                  ),
                if (onCollapse != null) IconButton(tooltip: t.conversation.collapse, onPressed: onCollapse, icon: const Icon(Icons.first_page)),
              ],
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _ConversationListTile extends StatelessWidget {
  final ConversationPeerView view;
  final bool selected;
  final VoidCallback onTap;

  const _ConversationListTile({
    required this.view,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = view.online ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Stack(
      children: [
        if (selected)
          PositionedDirectional(
            start: 0,
            top: 10,
            bottom: 10,
            child: Container(
              width: 3,
              decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ListTile(
          selected: selected,
          dense: true,
          visualDensity: const VisualDensity(vertical: -1),
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          contentPadding: const EdgeInsetsDirectional.only(start: 22, end: 16),
          onTap: onTap,
          leading: Icon(view.deviceType.icon, color: textColor),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  view.alias,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(color: textColor),
                ),
              ),
              const SizedBox(width: 6),
              // 在线状态：语义是"在线/未发现"（不变量 8），不是"已连接"
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: view.online ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                ),
              ),
              if (!view.online) ...[
                const SizedBox(width: 5),
                Text(t.general.offline, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
          subtitle: Text(
            _subtitle(context, view),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: textColor.withValues(alpha: 0.7)),
          ),
          // 活跃收发指示：仅小图标提示，不提供任何操作（取消属于原传输 provider）
          trailing: (view.hasActiveSend || view.hasActiveReceive)
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                )
              : null,
        ),
      ],
    );
  }

  /// 副标题：最后一条记录摘要；无记录时展示连接状态。
  String _subtitle(BuildContext context, ConversationPeerView view) {
    final last = view.lastEntry;
    if (last == null) {
      return view.online ? t.conversation.selectDevice : '';
    }
    final date = _formatDate(last.createdAt);
    final label = last.text ?? (last.files.isNotEmpty ? t.general.files : '');
    return label.isEmpty ? date : '$date · $label';
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
