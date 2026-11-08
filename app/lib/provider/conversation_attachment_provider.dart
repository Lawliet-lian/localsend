import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/conversation_attachment_cache.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('ConversationAttachment');

class ConversationAttachmentState {
  /// 选择器是否正在打开（含 picker 弹层与文件转换期间）。
  /// 这是唯一的 UI 状态字段，不含文字正文/路径等敏感内容，默认 toString 即脱敏。
  final bool picking;

  const ConversationAttachmentState({this.picking = false});
}

final conversationAttachmentProvider = NotifierProvider<ConversationAttachmentService, ConversationAttachmentState>((ref) {
  return ConversationAttachmentService();
});

final conversationAttachmentEnabledProvider = ViewProvider((ref) {
  return !ref.watch(conversationAttachmentProvider.select((s) => s.picking));
});

class ConversationAttachmentService extends Notifier<ConversationAttachmentState> {
  @override
  ConversationAttachmentState init() => const ConversationAttachmentState();

  Future<void> pickAndSend(BuildContext context, {required Device target}) async {
    return _pickAndSend(context, target: target);
  }

  Future<void> pickAndSendOption(BuildContext context, {required Device target, required FilePickerOption option}) =>
      _pickAndSend(context, target: target, option: option);

  Future<void> sendDroppedFiles(BuildContext context, {required Device target, required List<DropItem> files}) =>
      _pickAndSend(context, target: target, droppedFiles: files);

  Future<void> _pickAndSend(BuildContext context, {required Device target, FilePickerOption? option, List<DropItem>? droppedFiles}) async {
    if (state.picking) {
      if (droppedFiles != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.conversation.dropFailed)));
      }
      return;
    }

    state = const ConversationAttachmentState(picking: true);
    final cache = ConversationAttachmentCache();
    var submitted = false;
    try {
      final pendingFiles = droppedFiles != null
          ? _convertDroppedFiles(droppedFiles, cache)
          : option == null
          ? pickFiles(context, cache)
          : _pickOption(context, cache, option);
      final files = await pendingFiles;
      if (files.isEmpty || !context.mounted || target.fingerprint.trim().isEmpty) {
        if (droppedFiles != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.conversation.dropFailed)));
        }
        return;
      }
      final peerKey = ConversationPeer.peerKeyFor(target.fingerprint);
      final currentTarget = ref.read(conversationPeerViewsProvider).firstWhereOrNull((view) => view.peerKey == peerKey)?.device;
      if (currentTarget == null) {
        if (droppedFiles != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.conversation.offline)));
        }
        return;
      }

      unawaited(
        ref
            .notifier(sendProvider)
            .startSession(
              target: currentTarget,
              files: List<CrossFile>.unmodifiable(files),
              background: true,
              presentation: TransferPresentation.conversation,
              attachmentCache: cache.hasFiles ? cache : null,
            )
            .catchError((Object error) => _logger.warning('Failed to start attachment transfer', error)),
      );
      submitted = true;
    } catch (e) {
      _logger.warning('Failed to pick and send attachment', e);
      if (droppedFiles != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.conversation.dropFailed)));
      }
    } finally {
      if (!submitted) {
        cache.close();
      }
      state = const ConversationAttachmentState(picking: false);
    }
  }

  Future<List<CrossFile>> _convertDroppedFiles(List<DropItem> files, ConversationAttachmentCache cache) async {
    final selection = RefenaContainer();
    try {
      final regularFiles = <DropItem>[];
      for (final file in files) {
        final bookmark = file.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) await cache.holdBookmark(bookmark);
        final type = await FileSystemEntity.type(file.path);
        if (type == FileSystemEntityType.directory) {
          await selection.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(file.path));
        } else if (type == FileSystemEntityType.file) {
          regularFiles.add(file);
        } else {
          throw FileSystemException('Cannot read dropped item', file.path);
        }
      }
      if (regularFiles.isNotEmpty) {
        await selection
            .redux(selectedSendingFilesProvider)
            .dispatchAsync(
              AddFilesAction(files: regularFiles, converter: CrossFileConverters.convertXFile),
            );
      }
      return cache.stage(List<CrossFile>.of(selection.read(selectedSendingFilesProvider)), copyImportedFiles: false);
    } finally {
      selection.disposeContainer();
    }
  }

  @visibleForTesting
  Future<List<CrossFile>> pickFiles(BuildContext context, ConversationAttachmentCache cache) async {
    final options = FilePickerOption.getOptionsForPlatform();
    final isAndroid = checkPlatform([TargetPlatform.android]);
    final option = await AddFileDialog.chooseOption(
      context,
      options: isAndroid ? options.where((o) => o != FilePickerOption.text && o != FilePickerOption.clipboard).toList() : options,
      mediaLabel: isAndroid ? t.conversation.album : null,
    );
    if (option == null || !context.mounted) {
      return const [];
    }

    return _pickOption(context, cache, option);
  }

  Future<List<CrossFile>> _pickOption(BuildContext context, ConversationAttachmentCache cache, FilePickerOption option) async {
    final selection = RefenaContainer();
    try {
      await ref.global.dispatchAsync(PickFileAction(option: option, context: context, selectionRef: selection));
      final files = selection.read(selectedSendingFilesProvider);
      if (!checkPlatformIsDesktop() && files.any((file) => file.path != null && !file.path!.startsWith('content://'))) {
        return await cache.stage(files, copyImportedFiles: checkPlatform([TargetPlatform.iOS]) && option == FilePickerOption.file);
      }
      return files;
    } finally {
      selection.disposeContainer();
    }
  }
}
