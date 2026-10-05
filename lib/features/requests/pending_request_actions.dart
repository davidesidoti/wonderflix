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
/// §9.4). Con [busy] c'è solo l'indicatore.
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
  Timer? _confirm;

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
    if (widget.busy) {
      return const SizedBox.square(
          dimension: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }
    final l = AppLocalizations.of(context);
    final confirming = _confirm != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          // Stessa chiave nei due tempi: il fuoco da tastiera resta.
          key: const Key('request-decline'),
          onPressed: confirming ? _decline : _ask,
          style: TextButton.styleFrom(
              foregroundColor: confirming ? WfColors.error : WfColors.creamMuted),
          child: Text(confirming ? l.requestsDeclineConfirm : l.requestsDecline),
        ),
        const SizedBox(width: 8),
        WfButton.primary(
          label: l.requestsApprove,
          icon: LucideIcons.check,
          onPressed: widget.onApprove,
        ),
      ],
    );
  }
}
