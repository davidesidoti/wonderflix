import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'wf_buttons.dart';
import 'wf_dialog.dart';
import 'wf_dialog_parts.dart';

/// Una conferma: titolo, messaggio, [cancelLabel] e il pulsante
/// [confirmLabel]. `true` solo con la conferma.
Future<bool> showWfConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final confirmed = await showWfDialog<bool>(
    context,
    semanticLabel: title,
    fullPageWhenCompact: false,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WfDialogHeader(title: title),
        const SizedBox(height: 16),
        Text(message),
      ],
    ),
    footer: (context) => WfDialogFooter(
      cancelLabel: cancelLabel,
      onCancel: () => Navigator.of(context).pop(false),
      primary: WfButton.primary(
        label: confirmLabel,
        icon: LucideIcons.check,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ),
  );
  return confirmed ?? false;
}
