import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/conversation_attachment_cache.dart';
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
    if (state.picking) {
      return;
    }

    state = const ConversationAttachmentState(picking: true);
    final cache = ConversationAttachmentCache();
    var submitted = false;
    try {
      final files = await pickFiles(context, cache);
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
  Future<List<CrossFile>> pickFiles(BuildContext context, ConversationAttachmentCache cache) async {
    final option = await AddFileDialog.chooseOption(context);
    if (option == null || !context.mounted) {
      return const [];
    }

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
