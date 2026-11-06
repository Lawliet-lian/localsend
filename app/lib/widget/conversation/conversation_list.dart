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

  const ConversationList({
    super.key,
    required this.views,
    required this.selectedPeerKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (views.isEmpty) {
      // 空态：没有任何可发现的设备或历史会话
      return Center(
        child: Text(
          t.conversation.empty,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    // ListTile 需要 Material 祖先；组件自身不假设被 Scaffold 包裹，主动提供透明 Material
    return Material(
      type: MaterialType.transparency,
      child: ListView.separated(
        itemCount: views.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final view = views[index];
          return _ConversationListTile(
            view: view,
            selected: view.peerKey == selectedPeerKey,
            onTap: () => onTap(view.peerKey),
          );
        },
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

    return ListTile(
      selected: selected,
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
    );
  }

  /// 副标题：最后一条记录摘要；无记录时展示连接状态。
  String _subtitle(BuildContext context, ConversationPeerView view) {
    final last = view.lastEntry;
    if (last == null) {
      return view.online ? t.conversation.selectDevice : t.general.offline;
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
