import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';

/// Una conferma della pagina Amministrazione: titolo, messaggio, "Annulla"
/// e il pulsante [confirmLabel]. `true` solo con la conferma.
Future<bool> showAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showWfDialog<bool>(
    context,
    semanticLabel: title,
    builder: (context) {
      final l = AppLocalizations.of(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Text(message),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l.adminCancel),
              ),
              const SizedBox(width: 12),
              FilledButton(
                // Il tema fa i FilledButton larghi all'infinito: in una Row
                // servono larghi quanto il testo.
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
