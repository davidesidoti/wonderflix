import 'package:flutter/material.dart';

import 'wf_dialog.dart';

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
              child: Text(cancelLabel),
            ),
            const SizedBox(width: 12),
            // `Flexible`: per le etichette lunghe, il testo ingrandito o le
            // altre lingue; il testo va a capo nel pulsante invece di
            // sbordare dalla finestra. Con un'etichetta corta il pulsante
            // resta largo quanto il testo.
            Flexible(
              child: FilledButton(
                // Il tema fa i FilledButton larghi all'infinito: in una Row
                // servono larghi quanto il testo.
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
