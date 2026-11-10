import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/conversation_file_draft_provider.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/conversation_attachment_cache.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/macos_channel.dart' as macos;
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

  Future<void> pickToDraft(BuildContext context, {required String peerKey, FilePickerOption? option}) async {
    if (state.picking) return;
    state = const ConversationAttachmentState(picking: true);
    final cache = ConversationAttachmentCache();
    try {
      final pending = option != null
          ? _pickOption(context, cache, option)
          : checkPlatform([TargetPlatform.macOS])
          ? _pickMacAttachments(cache)
          : pickFiles(context, cache);
      final files = await pending;
      ref.notifier(conversationFileDraftProvider).addPicked(peerKey, files, cache);
    } catch (error) {
      cache.close();
      _logger.warning('Failed to pick attachment', error);
    } finally {
      state = const ConversationAttachmentState(picking: false);
    }
  }

  Future<void> addDroppedFilesToDraft(BuildContext context, {required String peerKey, required List<DropItem> files}) async {
    if (state.picking) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.conversation.dropFailed)));
      return;
    }
    state = const ConversationAttachmentState(picking: true);
    final cache = ConversationAttachmentCache();
    try {
      final selected = await convertDroppedFiles(files, cache);
      if (selected.isEmpty) {
        cache.close();
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.conversation.dropFailed)));
        return;
      }
      ref.notifier(conversationFileDraftProvider).addPicked(peerKey, selected, cache);
    } catch (error) {
      cache.close();
      _logger.warning('Failed to add dropped attachments', error);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.conversation.dropFailed)));
    } finally {
      state = const ConversationAttachmentState(picking: false);
    }
  }

  Future<void> _pickAndSend(BuildContext context, {required Device target, FilePickerOption? option}) async {
    if (state.picking) return;

    state = const ConversationAttachmentState(picking: true);
    final cache = ConversationAttachmentCache();
    var submitted = false;
    try {
      final pendingFiles = option == null ? pickFiles(context, cache) : _pickOption(context, cache, option);
      final files = await pendingFiles;
      if (files.isEmpty || !context.mounted || target.fingerprint.trim().isEmpty) {
        return;
      }
      final peerKey = ConversationPeer.peerKeyFor(target.fingerprint);
      final currentTarget = ref.read(conversationPeerViewsProvider).firstWhereOrNull((view) => view.peerKey == peerKey)?.device;
      if (currentTarget == null) {
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
    } finally {
      if (!submitted) {
        cache.close();
      }
      state = const ConversationAttachmentState(picking: false);
    }
  }

  @visibleForTesting
  Future<List<CrossFile>> convertDroppedFiles(List<DropItem> files, ConversationAttachmentCache cache) async {
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
    // 移动端不再主动收起键盘：AddFileDialog.chooseOption 的弹层不抢占焦点并自动抬到键盘上方，
    // 键盘保持展开、聊天区不随之重排，弹层动画即可保持流畅。
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

  Future<List<CrossFile>> _pickMacAttachments(ConversationAttachmentCache cache) async {
    final items = await macos.pickConversationAttachments();
    final selection = RefenaContainer();
    try {
      final files = <File>[];
      for (final (path, bookmark) in items) {
        await cache.holdBookmark(bookmark);
        final type = await FileSystemEntity.type(path);
        if (type == FileSystemEntityType.directory) {
          await selection.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(path));
        } else if (type == FileSystemEntityType.file) {
          files.add(File(path));
        } else {
          throw FileSystemException('Cannot read selected item', path);
        }
      }
      if (files.isNotEmpty) {
        await selection.redux(selectedSendingFilesProvider).dispatchAsync(AddFilesAction(files: files, converter: CrossFileConverters.convertFile));
      }
      return cache.stage(List<CrossFile>.of(selection.read(selectedSendingFilesProvider)), copyImportedFiles: false);
    } finally {
      selection.disposeContainer();
    }
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
