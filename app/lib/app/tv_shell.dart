import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/tonight/tonight_dialog.dart';
import '../l10n/gen/app_localizations.dart';
import 'back_navigation.dart';
import 'tv_account_menu.dart';
import 'tv_sidebar.dart';

export 'tv_sidebar.dart' show tvSidebarCollapsedWidth, tvSidebarExpandedWidth;

/// Entro questo tempo dal primo Indietro dalla radice, il secondo esce.
const tvExitWindow = Duration(seconds: 2);

/// Struttura delle schermate autenticate sulla TV: la barra laterale a
/// sinistra, il contenuto accanto. Niente barra in alto né pulsanti del PC.
///
/// Indietro: da una pagina profonda torna indietro come sempre; da una voce
/// della barra porta a `/home`; da `/home` chiede di premerlo di nuovo entro
/// [tvExitWindow] per uscire.
class TvShell extends ConsumerStatefulWidget {
  const TvShell({
    super.key,
    required this.child,
    @visibleForTesting this.onTonight,
    @visibleForTesting this.onExit,
  });

  final Widget child;

  /// Al posto di aprire la finestra di Stasera.
  final VoidCallback? onTonight;

  /// Al posto di `SystemNavigator.pop`.
  final VoidCallback? onExit;

  @override
  ConsumerState<TvShell> createState() => _TvShellState();
}

class _TvShellState extends ConsumerState<TvShell> {
  final _content = FocusScopeNode(debugLabel: 'tv-content');

  /// Timer della finestra del doppio Indietro; attivo = il primo c'è già stato.
  Timer? _exitTimer;

  @override
  void dispose() {
    _exitTimer?.cancel();
    _content.dispose();
    super.dispose();
  }

  void _select(String route) {
    if (route == tvTonightEntry) {
      (widget.onTonight ?? () => unawaited(openTonight(context, ref)))();
      return;
    }
    context.go(route);
    // La pagina nuova ha le sue voci con `autofocus`; se nessuna prende il
    // focus (o la pagina è la stessa) lo si porta al primo del contenuto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_content.hasFocus) _content.requestFocus();
    });
  }

  void _onBack(bool didPop, Object? result) {
    if (didPop) return;
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    if (GoRouterState.of(context).uri.path != '/home') {
      router.go('/home');
      return;
    }
    if (_exitTimer?.isActive ?? false) {
      _exitTimer!.cancel();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      (widget.onExit ?? () => unawaited(SystemNavigator.pop()))();
      return;
    }
    _exitTimer = Timer(tvExitWindow, () {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).tvExitHint),
          duration: tvExitWindow,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Indietro lo gestiamo noi (`_onBack`): una pagina profonda la chiude
      // il navigatore prima di arrivare qui.
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              left: tvSidebarCollapsedWidth,
              child: FocusScope(
                node: _content,
                child: BackNavigationHandler(child: widget.child),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: TvSidebar(
                location: GoRouterState.of(context).uri.path,
                onSelect: _select,
                onAccount: () => unawaited(showTvAccountMenu(context, ref)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
