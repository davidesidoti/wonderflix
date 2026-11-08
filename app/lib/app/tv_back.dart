import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../ui/form_factor.dart';

/// Entro questo tempo dal primo Indietro dalla radice, il secondo esce.
const tvExitWindow = Duration(seconds: 2);

/// Il doppio Indietro per uscire dalla TV: il primo mostra l'avviso, il
/// secondo entro [tvExitWindow] esce.
class TvDoubleBackExit {
  Timer? _timer;

  /// Il primo Indietro c'è già stato e la finestra è aperta.
  bool get armed => _timer?.isActive ?? false;

  void cancel() => _timer?.cancel();

  /// Un Indietro dalla radice. [onExit] sostituisce `SystemNavigator.pop`.
  void press(BuildContext context, {VoidCallback? onExit}) {
    final messenger = ScaffoldMessenger.of(context);
    if (armed) {
      cancel();
      messenger.hideCurrentSnackBar();
      (onExit ?? () => unawaited(SystemNavigator.pop()))();
      return;
    }
    _timer = Timer(tvExitWindow, () {});
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tvExitHint),
          duration: tvExitWindow,
        ),
      );
  }
}

/// Sulla TV, Indietro in una schermata d'ingresso (fuori dalla shell): la
/// pagina è l'unica nel navigatore e Indietro chiuderebbe l'app subito.
/// Fa [onBack] se c'è e dice di averlo gestito, altrimenti il doppio
/// Indietro per uscire. Fuori dalla TV non cambia niente.
class TvBackGuard extends StatefulWidget {
  const TvBackGuard({
    super.key,
    required this.child,
    this.onBack,
    @visibleForTesting this.onExit,
  });

  final Widget child;

  /// `true` se ha gestito Indietro (chiuso un pannello, annullato...).
  final bool Function()? onBack;

  /// Al posto di `SystemNavigator.pop`.
  final VoidCallback? onExit;

  @override
  State<TvBackGuard> createState() => _TvBackGuardState();
}

class _TvBackGuardState extends State<TvBackGuard> {
  final _exit = TvDoubleBackExit();

  @override
  void dispose() {
    _exit.cancel();
    super.dispose();
  }

  void _onBack(bool didPop, Object? result) {
    if (didPop) return;
    if (widget.onBack?.call() ?? false) return;
    _exit.press(context, onExit: widget.onExit);
  }

  @override
  Widget build(BuildContext context) {
    if (!FormFactor.of(context).tv) return widget.child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: widget.child,
    );
  }
}
