import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:pasteboard/pasteboard.dart';

/// 会话输入栏（P6c）：纯文字消息的草稿输入与发送。
///
/// dumb 参数化组件（与 P4 系列一致）：不 watch provider，数据与回调全部由接线层注入。
/// 行为合同（方案 6.2 / P6c 门槛）：
/// - 发出的文字**原样传出**：不 trim、不丢失换行；
/// - 防重复发送锁只针对"正在提交的一次动作"：提交即上锁并清空输入框，
///   直到用户重新输入非空文本才解锁——双击只会发出第一条（不把 session 时长当阻塞）；
/// - [enabled] 为 false（离线设备）时禁止发送，输入框仍可编辑保留草稿。
///
/// P9b 附件「即选即发」：[onPickAttachment] 非 null 时渲染附件按钮（ dumb 合同：
/// 是否支持由接线层决定，null 则按钮不出现，保护既有纯文字调用点）；
/// [attachmentEnabled] 为 false 时按钮置灰，例如选择器已打开。选择器弹层内的平台选项过滤由接线层复用
/// FilePickerOption.getOptionsForPlatform 完成，本组件不感知平台能力。
class ConversationComposer extends StatefulWidget {
  /// 当前设备的草稿初值。切换设备时调用方必须传不同的 ValueKey 触发重建，
  /// 避免上一设备的输入残留串到别的会话。
  final String initialValue;

  /// 是否允许发送（离线设备为 false）。
  final bool enabled;

  /// 输入内容变化（接线层用于按 peerKey 同步草稿；空文本等价删草稿的语义由 provider 处理）。
  final ValueChanged<String> onChanged;

  /// 发送回调，收到**未经修剪**的完整文本。
  final ValueChanged<String> onSend;
  final Uint8List? imageDraft;
  final ValueChanged<Uint8List?>? onImageDraftChanged;
  final void Function(String, Uint8List)? onSendImage;
  final List<CrossFile> fileDrafts;
  final Future<void> Function(List<String>)? onPasteFiles;
  final ValueChanged<int>? onRemoveFile;
  final void Function(String, Uint8List?, List<CrossFile>)? onSendFiles;

  /// 附件选择回调（P9b）：null 时不渲染附件按钮（接线层未接入/设备离线）。
  final VoidCallback? onPickAttachment;
  final ValueChanged<FilePickerOption>? onPickAttachmentOption;

  /// 附件按钮是否可用（P9b 门槛投影）：仅影响按钮置灰，不影响文字输入。
  final bool attachmentEnabled;

  const ConversationComposer({
    super.key,
    required this.initialValue,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
    this.imageDraft,
    this.onImageDraftChanged,
    this.onSendImage,
    this.fileDrafts = const [],
    this.onPasteFiles,
    this.onRemoveFile,
    this.onSendFiles,
    this.onPickAttachment,
    this.onPickAttachmentOption,
    this.attachmentEnabled = true,
  });

  @override
  State<ConversationComposer> createState() => _ConversationComposerState();
}

class _ConversationComposerState extends State<ConversationComposer> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  /// 提交锁：一次发送动作期间只允许一次提交（见类注释的行为合同）。
  bool _locked = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    // 空文本、离线、或上一次提交尚未产生新输入：一律不发送
    if (!widget.enabled || _locked || (text.isEmpty && widget.imageDraft == null && widget.fileDrafts.isEmpty)) {
      return;
    }
    if (widget.fileDrafts.any((file) => file.path != null && !File(file.path!).existsSync())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.dialogs.cannotOpenFile.title)));
      return;
    }
    _locked = true;
    _controller.clear();
    // 草稿同步与发送都使用原文（不 trim）
    widget.onChanged('');
    final image = widget.imageDraft;
    if (widget.fileDrafts.isNotEmpty && widget.onSendFiles != null) {
      widget.onSendFiles!(text, image, List.of(widget.fileDrafts));
    } else if (image != null && widget.onSendImage != null) {
      widget.onSendImage!(text, image);
    } else {
      widget.onSend(text);
    }
  }

  Future<void> _paste() async {
    try {
      if (widget.onPasteFiles != null) {
        final files = Platform.isAndroid
            ? await const MethodChannel('org.localsend.localsend_app/localsend').invokeListMethod<String>('stageClipboardFiles') ?? <String>[]
            : await Pasteboard.files();
        if (files.isNotEmpty) {
          await widget.onPasteFiles!(files);
          if (mounted) setState(() => _locked = false);
          return;
        }
        if (!mounted) return;
      }
      if (Platform.isAndroid) {
        final image = await const MethodChannel('org.localsend.localsend_app/localsend').invokeMethod<Uint8List>('readClipboardImage');
        if (!mounted) return;
        if (image != null && image.isNotEmpty) {
          widget.onImageDraftChanged?.call(image);
          setState(() => _locked = false);
          return;
        }
      }
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted) return;
      if (text != null && text.isNotEmpty) {
        final value = _controller.value;
        final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
        final next = value.text.replaceRange(selection.start, selection.end, text);
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: selection.start + text.length),
        );
        _onChanged(next);
        return;
      }
      final Uint8List? image = Platform.isAndroid ? null : await Pasteboard.image;
      if (!mounted) return;
      if (image != null && image.isNotEmpty) {
        widget.onImageDraftChanged?.call(image);
        setState(() => _locked = false);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.dialogs.cannotOpenFile.title)));
    }
  }

  void _onChanged(String text) {
    if (text.isNotEmpty && _locked) {
      setState(() => _locked = false);
    }
    widget.onChanged(text);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
      unawaited(_paste());
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter && event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final composing = _controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isAltPressed) return KeyEventResult.ignored;
    if (keyboard.isShiftPressed || keyboard.isMetaPressed) {
      final value = _controller.value;
      final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
      final text = value.text.replaceRange(selection.start, selection.end, '\n');
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: selection.start + 1),
      );
      _onChanged(text);
    } else {
      _submit();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // TextField/IconButton 需要 Material 祖先；组件不假设外部一定被 Scaffold 包裹
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.imageDraft != null)
                Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.memory(widget.imageDraft!, width: 88, height: 88, fit: BoxFit.contain),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        icon: const Icon(Icons.cancel),
                        tooltip: t.general.close,
                        onPressed: () => widget.onImageDraftChanged?.call(null),
                      ),
                    ),
                  ],
                ),
              if (widget.fileDrafts.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.fileDrafts.length,
                    itemBuilder: (context, i) => Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${widget.fileDrafts[i].name} (${widget.fileDrafts[i].size} B)', overflow: TextOverflow.ellipsis)),
                        IconButton(tooltip: t.general.close, onPressed: () => widget.onRemoveFile?.call(i), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 附件按钮（P9b）：接线层未传入回调时不渲染（不支持的入口不出现）；
                  // 门槛不满足或离线时置灰。tooltip 复用既有 t.general.add，不新增文案。
                  if (checkPlatformIsDesktop() && widget.onPickAttachmentOption != null)
                    ...[FilePickerOption.file, FilePickerOption.folder].map(
                      (option) => IconButton(
                        icon: Icon(option.icon),
                        tooltip: '${option.label} — ${t.conversation.attachmentImmediate}',
                        onPressed: widget.enabled && widget.attachmentEnabled ? () => widget.onPickAttachmentOption!(option) : null,
                      ),
                    )
                  else if (widget.onPickAttachment != null)
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      tooltip: '${t.general.add} — ${t.conversation.attachmentImmediate}',
                      onPressed: widget.enabled && widget.attachmentEnabled ? widget.onPickAttachment : null,
                    ),
                  Expanded(
                    child: Focus(
                      canRequestFocus: false,
                      onKeyEvent: checkPlatformIsDesktop() ? _onKeyEvent : null,
                      child: TextField(
                        controller: _controller,
                        contextMenuBuilder: (context, editable) {
                          final items = editable.contextMenuButtonItems.where((item) => item.type != ContextMenuButtonType.paste).toList();
                          items.add(
                            ContextMenuButtonItem(
                              type: ContextMenuButtonType.paste,
                              onPressed: () {
                                editable.hideToolbar();
                                unawaited(_paste());
                              },
                            ),
                          );
                          return AdaptiveTextSelectionToolbar.buttonItems(anchors: editable.contextMenuAnchors, buttonItems: items);
                        },
                        // 多行输入：换行是消息内容的一部分，绝不因键盘行为丢失
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          // 离线提示由详情顶栏统一展示，这里不重复文案；禁用态由输入框置灰表达
                          hintText: t.conversation.composeHint,
                          border: const OutlineInputBorder(borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          isDense: true,
                        ),
                        onChanged: _onChanged,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) => IconButton(
                      icon: const Icon(Icons.send),
                      tooltip: t.conversation.send,
                      // 不可发送时按钮置灰：离线、空文本或提交锁未释放
                      onPressed: widget.enabled && !_locked && (value.text.isNotEmpty || widget.imageDraft != null || widget.fileDrafts.isNotEmpty)
                          ? _submit
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
