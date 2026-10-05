import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';

/// Quanto resta "Conferma" dopo il primo clic su Rifiuta, come "Svuota"
/// della cassetta (decisione 1 del piano 15b).
const declineConfirmFor = Duration(seconds: 4);

/// Rifiuta (a due tempi) e Approva in una riga di "Da approvare" (spec I
/// §9.4). Con [busy] c'è solo l'indicatore, al centro dello spazio dei
/// pulsanti: la riga non cambia misura.
class PendingRequestActions extends StatefulWidget {
  const PendingRequestActions({
    super.key,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
  });

  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  State<PendingRequestActions> createState() => _PendingRequestActionsState();
}

class _PendingRequestActionsState extends State<PendingRequestActions> {
  /// La misura dell'indicatore.
  static const _spinnerSize = 20.0;

  Timer? _confirm;

  @override
  void didUpdateWidget(PendingRequestActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Un invio in corso chiude la conferma: quando i pulsanti tornano
    // (un errore, per esempio) Rifiuta riparte da capo.
    if (widget.busy && !oldWidget.busy) {
      _confirm?.cancel();
      _confirm = null;
    }
  }

  @override
  void dispose() {
    _confirm?.cancel();
    super.dispose();
  }

  void _ask() {
    _confirm?.cancel();
    setState(() {
      _confirm = Timer(declineConfirmFor, () {
        if (mounted) setState(() => _confirm = null);
      });
    });
  }

  void _decline() {
    _confirm?.cancel();
    setState(() => _confirm = null);
    widget.onDecline();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final confirming = _confirm != null;
    // Con `busy` i pulsanti restano al loro posto ma non si vedono e non si
    // toccano, e l'indicatore sta sopra: la riga non salta.
    final stack = Stack(
      alignment: Alignment.center,
      children: [
        Visibility(
          visible: !widget.busy,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                // Stessa chiave nei due tempi: il fuoco da tastiera resta.
                key: const Key('request-decline'),
                onPressed: confirming ? _decline : _ask,
                style: TextButton.styleFrom(
                    foregroundColor:
                        confirming ? WfColors.error : WfColors.creamMuted),
                child: Text(
                  confirming ? l.requestsDeclineConfirm : l.requestsDecline,
                  // Lo screen reader sente cosa si conferma.
                  semanticsLabel:
                      confirming ? l.requestsDeclineConfirmLabel : null,
                ),
              ),
              const SizedBox(width: 8),
              WfButton.primary(
                label: l.requestsApprove,
                icon: LucideIcons.check,
                onPressed: widget.onApprove,
              ),
            ],
          ),
        ),
        if (widget.busy)
          SizedBox.square(
            dimension: _spinnerSize,
            child: CircularProgressIndicator(
                strokeWidth: 2, semanticsLabel: l.requestsWorking),
          ),
      ],
    );
    // Il clic sull'area dei pulsanti nascosti non deve arrivare alla riga
    // (aprirebbe la richiesta): solo con `busy` un rilevatore opaco lo
    // assorbe. L'albero resta lo stesso nei due casi, così il fuoco dei
    // pulsanti non va perso.
    return GestureDetector(
      behavior: widget.busy ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      onTap: widget.busy ? () {} : null,
      // Un assorbitore per il mouse: non un'azione in più per lo screen reader.
      excludeFromSemantics: true,
      child: stack,
    );
  }
}
