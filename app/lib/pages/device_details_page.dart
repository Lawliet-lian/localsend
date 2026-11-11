import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/pages/verify_page.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/conversation_ui_provider.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/system_date_time_formatter.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/big_button.dart';
import 'package:localsend_app/widget/dialogs/favorite_delete_dialog.dart';
import 'package:localsend_app/widget/dialogs/favorite_edit_dialog.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Shows the general information of a discovered device and
/// the log of its retained discovery confirmations.
class DeviceDetailsPage extends StatefulWidget {
  final Device device;
  final bool promptRelink;

  const DeviceDetailsPage({required this.device, this.promptRelink = false});

  @override
  State<DeviceDetailsPage> createState() => _DeviceDetailsPageState();
}

class _DeviceDetailsPageState extends State<DeviceDetailsPage> with Refena {
  List<DeviceLog> _logs = const [];

  @override
  void initState() {
    super.initState();
    if (widget.promptRelink) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_relink());
      });
    }

    ensureRef((ref) async {
      final logs = await ref
          .redux(parentIsolateProvider)
          .dispatchAsyncTakeResult(IsolateDiscoveryDeviceLogsAction(fingerprint: widget.device.fingerprint));
      if (mounted) {
        setState(() => _logs = logs);
      }
    });
  }

  Future<void> _toggleFavorite(FavoriteDevice? favoriteEntry) async {
    if (favoriteEntry != null) {
      final result = await showDialog<bool>(
        context: context,
        builder: (_) => FavoriteDeleteDialog(favoriteEntry),
      );
      if (result == true) {
        await ref.redux(favoritesProvider).dispatchAsync(RemoveFavoriteAction(deviceFingerprint: widget.device.fingerprint));
      }
    } else {
      await showDialog(
        context: context,
        builder: (_) => FavoriteEditDialog(prefilledDevice: widget.device),
      );
    }
  }

  Future<void> _relink() async {
    final device = widget.device;
    final newKey = ConversationPeer.peerKeyFor(device.fingerprint);
    final views = ref.read(conversationPeerViewsProvider);
    final candidates = ref.read(favoritesProvider).where((favorite) {
      final key = ConversationPeer.peerKeyFor(favorite.fingerprint);
      return key != newKey && favorite.fingerprint.trim().isNotEmpty && !views.any((view) => view.peerKey == key && view.online);
    }).toList();
    final old = await showDialog<FavoriteDevice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deviceDetailsPage.relinkTitle),
        content: SizedBox(
          width: 480,
          child: candidates.isEmpty
              ? Text(t.deviceDetailsPage.relinkEmpty)
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.deviceDetailsPage.relinkSelect),
                      for (final candidate in candidates)
                        ListTile(
                          title: Text(candidate.alias),
                          subtitle: SelectableText(candidate.fingerprint),
                          onTap: () => Navigator.pop(context, candidate),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.general.cancel))],
      ),
    );
    if (old == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deviceDetailsPage.relinkTitle),
        content: SingleChildScrollView(
          child: SelectableText('${t.deviceDetailsPage.relinkWarning}\n\n${old.alias}\n${old.fingerprint}\n\n${device.alias}\n${device.fingerprint}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.general.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.general.confirm)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final oldKey = ConversationPeer.peerKeyFor(old.fingerprint);
    final currentViews = ref.read(conversationPeerViewsProvider);
    if (currentViews.any((view) => (view.peerKey == oldKey || view.peerKey == newKey) && (view.hasActiveSend || view.hasActiveReceive)) ||
        currentViews.any((view) => view.peerKey == oldKey && view.online) ||
        !currentViews.any((view) => view.peerKey == newKey && view.online)) {
      context.showSnackBar(t.deviceDetailsPage.relinkUnavailable);
      return;
    }
    try {
      await ref
          .redux(conversationProvider)
          .dispatchAsync(
            RelinkConversationAction(
              oldPeer: ConversationPeer(peerKey: oldKey, fingerprint: old.fingerprint, alias: old.alias, deviceType: device.deviceType),
              newPeer: ConversationPeer(peerKey: newKey, fingerprint: device.fingerprint, alias: device.alias, deviceType: device.deviceType),
            ),
          );
      await ref.redux(favoritesProvider).dispatchAsync(RelinkFavoriteAction(oldFavorite: old, device: device));
      ref.notifier(conversationUiProvider).selectPeer(newKey);
      if (mounted) context.showSnackBar(t.deviceDetailsPage.relinkSuccess);
    } catch (_) {
      if (mounted) context.showSnackBar(t.deviceDetailsPage.relinkFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final favoriteEntry = ref.watch(favoritesProvider).findDevice(device);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.deviceDetailsPage.title),
      ),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BigButton(
                icon: favoriteEntry != null ? Icons.favorite : Icons.favorite_border,
                label: t.deviceDetailsPage.favorite,
                filled: favoriteEntry != null,
                width: 120,
                onTap: () async => await _toggleFavorite(favoriteEntry),
              ),
              const SizedBox(width: 20),
              BigButton(
                icon: Icons.verified_user,
                label: t.deviceDetailsPage.verify,
                filled: false,
                width: 120,
                onTap: () async => await context.push(
                  () => VerifyPage(
                    fingerprint: CombinedFingerprint.load(context, device.fingerprint),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          OutlinedButton.icon(
            onPressed: widget.device.fingerprint.trim().isEmpty ? null : _relink,
            icon: const Icon(Icons.link),
            label: Text(t.deviceDetailsPage.relinkTitle),
          ),
          const SizedBox(height: 20),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
              for (final entry in {
                t.deviceDetailsPage.info.name: device.alias,
                t.deviceDetailsPage.info.version: t.deviceDetailsPage.info.protocol(version: device.version),
                if (device.ip != null) t.deviceDetailsPage.info.address: '${device.ip}:${device.port}',
              }.entries)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 15, bottom: 5),
                      child: Text(entry.key, style: const TextStyle(color: Colors.grey)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: SelectableText(entry.value),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text(t.deviceDetailsPage.logs.title, style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: t.general.copy,
                icon: const Icon(Icons.copy),
                onPressed: _logs.isEmpty
                    ? null
                    : () async {
                        try {
                          await Clipboard.setData(
                            ClipboardData(
                              text: _logs.map((log) => '[${SystemDateTimeFormatter.time(context, log.timestamp)}] ${log.description}').join('\n'),
                            ),
                          );
                          if (context.mounted) {
                            context.showSnackBar(t.general.copiedToClipboard);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            context.showSnackBar('${t.general.error}: $e');
                          }
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_logs.isEmpty)
            Text(t.deviceDetailsPage.logs.empty, style: const TextStyle(color: Colors.grey))
          else
            ..._logs.map(
              (log) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('[${SystemDateTimeFormatter.time(context, log.timestamp)}]'),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(log.description),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension on DeviceLog {
  String get description {
    final protocol = channel.https ? 'HTTPS' : 'HTTP';
    return switch (kind) {
      DeviceLogKind.discovered => t.deviceDetailsPage.logs.discovered(protocol: protocol, host: channel.host),
      DeviceLogKind.updated => t.deviceDetailsPage.logs.updated(protocol: protocol, host: channel.host),
    };
  }
}
