import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_isolates/model/file_type.dart';

/// 单条会话记录的只读气泡（方案 6.2）。
///
/// - 方向：send 右对齐、receive 左对齐；每次传输恰好一条气泡（批量文件放同一气泡内）。
/// - 发送操作由调用方传入，气泡只负责布局。
class ConversationEntryTile extends StatefulWidget {
  final ConversationEntry entry;
  final Widget? transferControls;

  const ConversationEntryTile({super.key, required this.entry, this.transferControls});

  /// 超过该字符数的文字气泡默认折叠（避免固定高度裁剪丢内容，方案 6.2）。
  static const _collapsedChars = 300;

  @override
  State<ConversationEntryTile> createState() => _ConversationEntryTileState();
}

class _ConversationEntryTileState extends State<ConversationEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    final isSend = entry.direction == ConversationDirection.send;

    final bubbleColor = isSend ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest;
    final textColor = isSend ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface;

    final text = entry.text;
    final needsCollapse = text != null && text.length > ConversationEntryTile._collapsedChars;

    final children = <Widget>[
      // 状态行：outcome 图标 + 状态文案 + 创建时间
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Icon(_outcomeIcon(entry.outcome), size: 14, color: _outcomeColor(theme, entry.outcome)),
          Text(
            _outcomeLabel(entry.outcome, isSend: isSend),
            style: theme.textTheme.labelSmall?.copyWith(color: textColor.withValues(alpha: 0.7)),
          ),
          Text(
            _formatTime(entry.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(color: textColor.withValues(alpha: 0.7)),
          ),
        ],
      ),
      const SizedBox(height: 4),
    ];

    if (entry.kind == ConversationEntryKind.text && text != null) {
      children.add(
        SelectableText(
          // 发出的内容不 trim、保留换行（方案 6.2）
          text,
          style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
          maxLines: needsCollapse && !_expanded ? 8 : null,
        ),
      );
      if (needsCollapse) {
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? t.conversation.collapse : t.conversation.expand),
            ),
          ),
        );
      }
    } else {
      // 文件卡片：名称、大小、单文件结果（图片缩略图属于 P7，这里仅图标）
      for (final file in entry.files) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_fileTypeIcon(file.fileType), size: 18, color: textColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    file.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatSize(file.size),
                  style: theme.textTheme.labelSmall?.copyWith(color: textColor.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 4),
                Icon(_fileOutcomeIcon(file.outcome), size: 14, color: _fileOutcomeColor(theme, file.outcome)),
              ],
            ),
          ),
        );
      }
    }

    // 整体失败/取消原因展示（不伪装成成功，方案 5.2）
    final error = entry.error;
    if (error != null && error.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            error,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      );
    }
    if (widget.transferControls case final controls?) {
      children.add(controls);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      // 处于 ListView 滚动子项中，高度约束无限：Column 必须 min 收缩，
      // 气泡宽度由 Container maxWidth 限制，不再包 Flexible
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isSend ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isSend ? 12 : 4),
                bottomRight: Radius.circular(isSend ? 4 : 12),
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// outcome → 展示文案（slang，全部经 t.，方案第 10 节）。
///
/// P10 视角修正：取消类终态需区分“本端取消”与“对方取消”。
/// 发送气泡里 canceledBySender、接收气泡里 canceledByReceiver 都是“我自己取消的”，
/// 改用中性的 canceledBySelf（“本端已取消”），避免把自身动作描述成对方行为（P7b 遗留）。
/// 其余情况仍按发送方/接收方的客观视角展示。
String _outcomeLabel(ConversationOutcome outcome, {required bool isSend}) {
  // 本端主动取消：方向与取消发起方一致时用第一人称中性文案
  if ((isSend && outcome == ConversationOutcome.canceledBySender) || (!isSend && outcome == ConversationOutcome.canceledByReceiver)) {
    return t.conversation.outcome.canceledBySelf;
  }
  return switch (outcome) {
    ConversationOutcome.preparing => t.conversation.outcome.preparing,
    ConversationOutcome.waiting => t.conversation.outcome.waiting,
    ConversationOutcome.transferring => t.conversation.outcome.transferring,
    ConversationOutcome.finished => t.conversation.outcome.finished,
    ConversationOutcome.partialFailure => t.conversation.outcome.partialFailure,
    ConversationOutcome.declined => t.conversation.outcome.declined,
    ConversationOutcome.busy => t.conversation.outcome.busy,
    ConversationOutcome.tooManyAttempts => t.conversation.outcome.tooManyAttempts,
    ConversationOutcome.canceledBySender => t.conversation.outcome.canceledBySender,
    ConversationOutcome.canceledByReceiver => t.conversation.outcome.canceledByReceiver,
    ConversationOutcome.failed => t.conversation.outcome.failed,
    ConversationOutcome.incomplete => t.conversation.outcome.incomplete,
    ConversationOutcome.noFilesAccepted => t.conversation.outcome.noFilesAccepted,
  };
}

IconData _outcomeIcon(ConversationOutcome outcome) {
  return switch (outcome) {
    ConversationOutcome.preparing => Icons.build_outlined,
    ConversationOutcome.waiting => Icons.hourglass_empty,
    ConversationOutcome.transferring => Icons.swap_vert,
    ConversationOutcome.finished => Icons.check_circle_outline,
    ConversationOutcome.partialFailure => Icons.warning_amber_rounded,
    ConversationOutcome.declined => Icons.do_not_disturb_on_outlined,
    ConversationOutcome.busy => Icons.more_horiz,
    ConversationOutcome.tooManyAttempts => Icons.lock_outline,
    ConversationOutcome.canceledBySender => Icons.cancel_outlined,
    ConversationOutcome.canceledByReceiver => Icons.cancel_outlined,
    ConversationOutcome.failed => Icons.error_outline,
    ConversationOutcome.incomplete => Icons.pending_actions,
    ConversationOutcome.noFilesAccepted => Icons.skip_next,
  };
}

Color _outcomeColor(ThemeData theme, ConversationOutcome outcome) {
  return switch (outcome) {
    ConversationOutcome.finished => theme.colorScheme.primary,
    ConversationOutcome.partialFailure ||
    ConversationOutcome.failed ||
    ConversationOutcome.declined ||
    ConversationOutcome.tooManyAttempts ||
    ConversationOutcome.incomplete => theme.colorScheme.error,
    ConversationOutcome.busy || ConversationOutcome.canceledBySender || ConversationOutcome.canceledByReceiver => theme.colorScheme.outline,
    _ => theme.colorScheme.secondary,
  };
}

IconData _fileTypeIcon(FileType type) {
  return switch (type) {
    FileType.image => Icons.image_outlined,
    FileType.video => Icons.movie_outlined,
    FileType.pdf => Icons.picture_as_pdf_outlined,
    FileType.text => Icons.description_outlined,
    FileType.apk => Icons.android,
    FileType.other => Icons.insert_drive_file_outlined,
  };
}

IconData _fileOutcomeIcon(ConversationFileOutcome outcome) {
  return switch (outcome) {
    ConversationFileOutcome.pending => Icons.hourglass_empty,
    ConversationFileOutcome.skipped => Icons.skip_next,
    ConversationFileOutcome.success => Icons.check,
    ConversationFileOutcome.failure => Icons.close,
  };
}

Color? _fileOutcomeColor(ThemeData theme, ConversationFileOutcome outcome) {
  return switch (outcome) {
    ConversationFileOutcome.success => theme.colorScheme.primary,
    ConversationFileOutcome.failure => theme.colorScheme.error,
    _ => theme.colorScheme.outline,
  };
}

/// 本地时区 HH:mm（持久化时间为 UTC，UI 转本地，方案 5.2）。
String _formatTime(DateTime createdAt) {
  final local = createdAt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// 简单的二进制单位文件大小格式化（第一版仅展示用途，不引入新依赖）。
String _formatSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
