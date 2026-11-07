import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/network/conversation_send_recorder.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/transfer_presentation_provider.dart';
import 'package:localsend_app/widget/conversation/conversation_entry_tile.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

class ConversationSendEntryTile extends StatelessWidget {
  final ConversationEntry entry;

  const ConversationSendEntryTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final id = entry.localSessionId;
    if (entry.direction != ConversationDirection.send ||
        context.watch(transferPresentationProvider.select((p) => p[id])) != TransferPresentation.conversation) {
      return ConversationEntryTile(entry: entry);
    }
    final session = context.watch(sendProvider.select((sessions) => sessions[id]));
    if (session == null) {
      return ConversationEntryTile(entry: entry);
    }

    final sending = session.status == SessionStatus.sending;
    final active = sending || session.status == SessionStatus.waiting;
    final files = sending || session.status == SessionStatus.finishedWithErrors ? context.watch(fileTransferProvider) : null;
    final send = context.ref.notifier(sendProvider);
    final displayed = sending && files != null
        ? entry.copyWith(
            files: [
              for (final file in entry.files)
                file.copyWith(
                  outcome: ConversationSendRecorder.outcomeFromFileStatus(files.getStatus(sessionId: id, fileId: file.fileId)),
                ),
            ],
          )
        : entry;

    double? progress;
    if (sending && files != null) {
      var totalBytes = 0;
      var transferred = 0.0;
      var totalFiles = 0;
      var fileProgress = 0.0;
      var knownSizes = true;
      for (final file in session.files.values) {
        if (file.token == null) {
          continue;
        }
        final fraction = files.getProgress(sessionId: id, fileId: file.file.id).clamp(0.0, 1.0);
        totalFiles++;
        fileProgress += fraction;
        knownSizes = knownSizes && file.file.size >= 0;
        totalBytes += file.file.size;
        transferred += file.file.size * fraction;
      }
      if (totalFiles > 0) {
        progress = knownSizes && totalBytes > 0 ? transferred / totalBytes : fileProgress / totalFiles;
      }
    }
    final preparing = active && !sending && entry.outcome == ConversationOutcome.preparing && session.files.isNotEmpty;
    if (preparing) {
      progress = (session.hashedFileCount / session.files.length).clamp(0.0, 1.0);
    }

    return ConversationEntryTile(
      entry: displayed,
      transferControls: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preparing) Text(t.sendPage.calculatingChecksum(curr: session.hashedFileCount, n: session.files.length)),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 4),
                    Text(
                      '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          if (session.status == SessionStatus.finishedWithErrors && session.remoteSessionId?.isNotEmpty == true && files != null)
            for (final file in session.files.values)
              if (file.token?.isNotEmpty == true && files.canRetry(sessionId: id, fileId: file.file.id))
                TextButton(
                  onPressed: () => unawaited(send.retryConversationFile(id, file.file.id)),
                  child: Text(t.conversation.retryFile(name: file.file.fileName), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
          TextButton(
            onPressed: () => send.stopConversationSession(id, cancel: active),
            child: Text(active ? t.conversation.cancelSend : t.conversation.endSend),
          ),
        ],
      ),
    );
  }
}
