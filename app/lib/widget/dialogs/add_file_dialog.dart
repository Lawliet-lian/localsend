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

  const AddFileDialog({required this.options, this.onSelect});

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

  static Future<FilePickerOption?> chooseOption(BuildContext context) {
    AddFileDialog picker(BuildContext routeContext) => AddFileDialog(
      options: FilePickerOption.getOptionsForPlatform(),
      onSelect: (option) => Navigator.of(routeContext).pop(option),
    );
    if (checkPlatformIsDesktop()) {
      return showDialog<FilePickerOption>(context: context, builder: (context) => _desktopDialog(context, picker(context)));
    }
    return context.pushBottomSheet<FilePickerOption, CustomBottomSheet>(
      () => CustomBottomSheet(
        title: t.dialogs.addFile.title,
        description: t.dialogs.addFile.content,
        child: Builder(builder: picker),
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
            label: option.label,
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
