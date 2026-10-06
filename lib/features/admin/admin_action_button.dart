import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../../app/error_text.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';

final _log = Logger('admin');

/// Il pulsante di un'azione della pagina Amministrazione (spec J §12):
/// mentre l'azione è in corso è disattivato, così non parte due volte. Se
/// l'azione lancia un errore, compare un avviso con `describeError`; gli
/// esiti da dire (riuscita, errori particolari) li mostra l'azione stessa.
class AdminActionButton extends StatefulWidget {
  const AdminActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;

  /// `null`: disattivato.
  final Future<void> Function()? onPressed;

  @override
  State<AdminActionButton> createState() => _AdminActionButtonState();
}

class _AdminActionButtonState extends State<AdminActionButton> {
  bool _running = false;

  Future<void> _run(Future<void> Function() action) async {
    // Una pressione in più prima del ridisegno non fa ripartire l'azione.
    if (_running) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _running = true);
    try {
      await action();
    } on Object catch (error, stack) {
      // Un errore che non viene dal server è un difetto: resta nel log.
      if (error is! ApiException) {
        _log.warning('azione non riuscita', error, stack);
      }
      // Se il pulsante non c'è più (scheda o pagina cambiata) non c'è un
      // posto dove mostrare l'avviso: il `ScaffoldMessenger` potrebbe non
      // avere più nessuna `Scaffold`.
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.onPressed;
    return WfButton.secondary(
      label: widget.label,
      icon: widget.icon,
      onPressed:
          action == null || _running ? null : () => unawaited(_run(action)),
    );
  }
}
