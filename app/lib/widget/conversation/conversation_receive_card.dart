import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_receive_card_vm.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';

/// 会话内接收卡片（P7c）：待决请求的接受/拒绝、传输中的进度/取消、
/// 发送端取消后的关闭——全部接线回 serverProvider 原有动作。
///
/// dumb 组件合同（与 ConversationComposer 一致）：
/// - 不 watch 任何 provider，状态判定全部来自 [ConversationReceiveCardVm]；
/// - 勾选集合是纯 UI 局部状态（ValueNotifier），**不碰全局 selectedReceivingFilesProvider**
///   （方案 6.3：两套选择状态串用会互相清空）；
/// - 无生命周期动作：卡片不因出现/消失触发任何传输行为（返回/缩放不取消传输）。
class ConversationReceiveCard extends StatefulWidget {
  final ConversationReceiveCardVm vm;
  final void Function(Map<String, String> fileNameMap) onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  const ConversationReceiveCard({
    super.key,
    required this.vm,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
    required this.onClose,
  });

  @override
  State<ConversationReceiveCard> createState() => _ConversationReceiveCardState();
}

class _ConversationReceiveCardState extends State<ConversationReceiveCard> {
  /// 被拒绝的文件 id（默认全选：与旧 ReceivePage 的初始选择一致）。
  final Set<String> _deselected = {};

  /// 卡片按 sessionId 挂 key（接线层），切 session 重建本 widget，勾选状态天然不残留。
  Map<String, String> get _selectedFileNameMap => {
    for (final f in widget.vm.session.files.values)
      if (!_deselected.contains(f.file.id)) f.file.id: f.desiredName ?? f.file.fileName,
  };

  @override
  Widget build(BuildContext context) {
    // 卡片不自行订阅 provider：进度刷新由外层 conversationReceiveCardProvider watch
    // fileTransferProvider 驱动（sending 时传入新 vm → didUpdateWidget 重建），
    // 本组件仅持有纯局部勾选状态
    final vm = widget.vm;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行：图标 + "来自 X 的文件" + 文件数
            Row(
              children: [
                Icon(Icons.download_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.conversation.receiveCard.title(name: vm.senderAlias),
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  t.conversation.receiveCard.filesCount(n: vm.fileCount),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 文件列表：最多显示 4 行，超出折叠为"+n 更多"（第一版不做展开页）
            ...vm.session.files.values.take(4).map((f) => _fileRow(f.file.id, f.file.fileName, f.file.size, f.file.fileType)),
            if (vm.fileCount > 4)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: Text(
                  t.conversation.receiveCard.moreFiles(n: vm.fileCount - 4),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            const SizedBox(height: 4),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(String fileId, String name, int size, FileType fileType) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // 待决时可勾选；传输开始后选择已固化，只展示类型图标
          if (widget.vm.isWaiting)
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: !_deselected.contains(fileId),
                // 至少保留一个选择：全部取消等价于点"拒绝"，禁用最后一个勾选防止歧义
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _deselected.remove(fileId);
                  } else if (_deselected.length < widget.vm.fileCount - 1) {
                    _deselected.add(fileId);
                  }
                }),
              ),
            )
          else
            SizedBox(width: 28, child: Icon(_iconOf(fileType), size: 18, color: theme.colorScheme.outline)),
          Expanded(
            child: Text(name, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ),
          Text(size.asReadableFileSize, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final vm = widget.vm;
    final theme = Theme.of(context);

    if (vm.isWaiting) {
      final selected = _selectedFileNameMap;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: widget.onDecline,
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: Text(t.general.decline),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            // 无选中时禁用（acceptFileRequest 对空 map 走"消息确认"分支，必须挡掉）
            onPressed: selected.isEmpty ? null : () => widget.onAccept(selected),
            icon: const Icon(Icons.check_circle, size: 18),
            label: Text(t.general.accept),
          ),
        ],
      );
    }

    if (vm.isSending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: vm.totalProgress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${t.conversation.outcome.transferring} · ${(vm.totalProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall,
                ),
              ),
              TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                child: Text(t.general.cancel),
              ),
            ],
          ),
        ],
      );
    }

    // canceledBySender：提示 + 关闭（关闭仅清理 session，不发送任何取消通知）
    return Column(
      children: [
        Text(
          t.conversation.receiveCard.canceled,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.warning),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.onClose,
            icon: const Icon(Icons.check_circle, size: 18),
            label: Text(t.general.close),
          ),
        ),
      ],
    );
  }
}

/// 文件类型图标（卡片行展示用，与 FileType 枚举一一对应，无平台猜测）。
IconData _iconOf(FileType type) {
  return switch (type) {
    FileType.text => Icons.article_outlined,
    FileType.image => Icons.image_outlined,
    FileType.video => Icons.movie_outlined,
    FileType.pdf => Icons.picture_as_pdf_outlined,
    FileType.apk => Icons.android,
    FileType.other => Icons.insert_drive_file_outlined,
  };
}
