import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:routerino/routerino.dart';

/// 会话记录清除确认对话框（P9a-2）。
///
/// 通用组件：由调用方传入标题与正文，因此 P9a-2 的"清空全部"与 P9a-3 的"清空当前会话"
/// 复用同一对话框、仅文案不同。确认语义固定为"只清除会话记录，不删除真实文件、不取消进行中的传输"
/// （方案第 7 节 / 不变量 2）。返回 `true` 表示用户确认清除。
class ConversationClearDialog extends StatelessWidget {
  const ConversationClearDialog({
    super.key,
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          onPressed: () => context.pop(true),
          child: Text(t.general.delete),
        ),
      ],
    );
  }
}
