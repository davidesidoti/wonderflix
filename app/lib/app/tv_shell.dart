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

  final _sidebar = GlobalKey<TvSidebarState>();

  /// Pagina dell'ultima costruzione: cambiando, la finestra del doppio
  /// Indietro non vale più.
  String? _location;

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
      if (mounted && !_content.hasFocus) _focusContent();
    });
  }

  /// Porta il focus nel contenuto: all'elemento che lo aveva, alla voce con
  /// `autofocus` o alla prima. Mai su un nodo invisibile (lo scope stesso).
  void _focusContent() {
    _content.requestFocus();
    // Il focus cambia a fine microtask: solo allora si vede dove è finito.
    scheduleMicrotask(() {
      final primary = FocusManager.instance.primaryFocus;
      if (primary is FocusScopeNode) primary.nextFocus();
    });
  }

  /// Sinistra dal bordo sinistro del contenuto: la ricerca nel navigatore si
  /// ferma lì (ogni pagina è uno scope a sé), quindi si passa alla barra.
  KeyEventResult _onContentKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent ||
        event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    // In un campo di testo (e con Maiusc, Ctrl, Alt o Meta) Sinistra è del
    // campo: muove il cursore o la selezione.
    if (HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null ||
        primary.context?.findAncestorWidgetOfExactType<EditableText>() !=
            null) {
      return KeyEventResult.ignored;
    }
    if (!primary.focusInDirection(TraversalDirection.left)) {
      _sidebar.currentState?.focusEntryFor(GoRouterState.of(context).uri.path);
    }
    return KeyEventResult.handled;
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
    final location = GoRouterState.of(context).uri.path;
    if (location != _location) {
      _location = location;
      _exitTimer?.cancel();
    }
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
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onContentKey,
                  child: BackNavigationHandler(child: widget.child),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: TvSidebar(
                key: _sidebar,
                location: location,
                onFocusContent: _focusContent,
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
