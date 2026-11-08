import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// Shows the transport security of one direction of a device transfer.
class TransferSecurityLabel extends StatelessWidget {
  final bool? encrypted;
  final bool receiving;
  final bool showLabel;

  const TransferSecurityLabel({super.key, required this.encrypted, this.receiving = false, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = encrypted == null
        ? theme.colorScheme.outline
        : encrypted!
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    final labels = t.general.transferSecurity;
    final label = switch ((receiving, encrypted)) {
      (false, true) => labels.encryptedSend,
      (false, false) => labels.plaintextSend,
      (true, true) => labels.encryptedReceive,
      (true, false) => labels.plaintextReceive,
      (_, null) => labels.unknown,
    };

    final icon = Icon(
      encrypted == null
          ? Icons.help_outline
          : encrypted!
          ? Icons.lock
          : Icons.lock_open,
      size: encrypted == null ? 14 : 16,
      color: encrypted == true ? const Color(0xFFFF4D4F) : color,
    );
    if (!showLabel) return Tooltip(message: label, child: icon);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        icon,
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}
