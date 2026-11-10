import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/big_button.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class AddFileDialog extends StatelessWidget {
  final List<FilePickerOption> options;
  final ValueChanged<FilePickerOption>? onSelect;
  final String? mediaLabel;

  const AddFileDialog({required this.options, this.onSelect, this.mediaLabel});

  static Future<void> open({required BuildContext context, required List<FilePickerOption> options}) async {
    if (checkPlatformIsDesktop()) {
      await showDialog(
        context: context,
        builder: (context) => _desktopDialog(context, AddFileDialog(options: options)),
      );
    } else {
      await context.pushBottomSheet(
        () => CustomBottomSheet(
          title: t.dialogs.addFile.title,
          description: t.dialogs.addFile.content,
          child: AddFileDialog(options: options),
        ),
      );
    }
  }

  static Future<FilePickerOption?> chooseOption(BuildContext context, {List<FilePickerOption>? options, String? mediaLabel}) {
    AddFileDialog picker(BuildContext routeContext) => AddFileDialog(
      options: options ?? FilePickerOption.getOptionsForPlatform(),
      mediaLabel: mediaLabel,
      onSelect: (option) => Navigator.of(routeContext).pop(option),
    );
    if (checkPlatformIsDesktop()) {
      return showDialog<FilePickerOption>(context: context, builder: (context) => _desktopDialog(context, picker(context)));
    }
    // 移动端：不走 routerino 的 pushBottomSheet，直接调用 showModalBottomSheet 以便控制焦点：
    // - requestFocus: false：弹层入栈时不抢占焦点，会话输入框保持聚焦，软键盘不会被收起；
    //   键盘高度保持不变，聊天区无需随键盘收起逐帧重排，避免与弹层上滑动画叠加造成卡顿；
    // - 外层 Padding 按 viewInsets 把弹层整体抬到键盘上方，否则会被键盘遮住；
    // - isScrollControlled: true 解除默认 9/16 屏高上限，避免叠加键盘高度后内容被压缩溢出；
    // 其余参数（透明背景、无阴影、路由名）与 routerino 的 pushBottomSheet 保持一致。
    return showModalBottomSheet<FilePickerOption>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      requestFocus: false,
      routeSettings: const RouteSettings(name: 'CustomBottomSheet'),
      builder: (routeContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(routeContext).bottom),
        child: CustomBottomSheet(
          title: t.dialogs.addFile.title,
          description: t.dialogs.addFile.content,
          child: picker(routeContext),
        ),
      ),
    );
  }

  static Widget _desktopDialog(BuildContext context, AddFileDialog picker) {
    return AlertDialog(
      title: Text(t.dialogs.addFile.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(t.dialogs.addFile.content), const SizedBox(height: 20), picker],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.general.close))],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 15,
      runSpacing: 15,
      children: [
        ...options.map((option) {
          return BigButton(
            icon: option.icon,
            label: option == FilePickerOption.media ? mediaLabel ?? option.label : option.label,
            filled: true,
            onTap: () async {
              final select = onSelect;
              if (select != null) {
                select(option);
                return;
              }
              final ref = context.ref;
              await ref.global.dispatchAsync(PickFileAction(option: option, context: context));
              ref.global.dispatch(NavigateAction.popUntilRoot());
            },
          );
        }),
      ],
    );
  }
}
