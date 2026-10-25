import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/friends/friends_controller.dart';
import '../features/inbox/inbox_controller.dart';
import '../features/player/player_active.dart';
import '../ui/form_factor.dart';

/// I pannelli laterali della shell (spec F §8.3, spec G §7.5).
enum ShellPanel { none, friends, inbox, recommend, rate }

/// Il pannello laterale aperto: uno alla volta, aprirne uno chiude l'altro.
/// Aprire Amici rilegge gli amici; aprire e chiudere Notifiche lo dice alla
/// cassetta (letture e pallini). Ascolta solo il player, per chiudersi
/// quando si apre (la shell resta montata sotto): `build` non si ricostruisce
/// mai per altri provider, perché lo legge anche la gestione dei tasti
/// indietro. Si azzera quando nessuno lo guarda più (es. la shell smontata al
/// logout).
class ShellPanelController extends Notifier<ShellPanel> {
  @override
  ShellPanel build() {
    // Il player si apre sopra la shell: il pannello non resta aperto sotto
    // (la cassetta non segna lette le voci arrivate durante il film).
    ref.listen(playerActiveProvider, (_, active) {
      if (active) close();
    });
    return ShellPanel.none;
  }

  void open(ShellPanel panel) {
    if (panel == ShellPanel.none) {
      close();
      return;
    }
    if (state == panel) return;
    _leaving();
    state = panel;
    switch (panel) {
      case ShellPanel.friends:
        unawaited(ref.read(friendsControllerProvider.notifier).reload());
      case ShellPanel.inbox:
        ref.read(inboxControllerProvider.notifier).panelOpened();
      case ShellPanel.recommend:
      case ShellPanel.rate:
      case ShellPanel.none:
        // Il soggetto lo imposta chi apre, con `openRecommendPanel` o
        // `openRatePanel`.
        break;
    }
  }

  void close() {
    if (state == ShellPanel.none) return;
    _leaving();
    state = ShellPanel.none;
  }

  void toggle(ShellPanel panel) => state == panel ? close() : open(panel);

  /// Chiude [panel] se è ancora quello aperto (e il controller vive ancora).
  void closeIfOpen(ShellPanel panel) {
    if (ref.mounted && state == panel) close();
  }

  /// Il pannello di adesso sta per chiudersi.
  void _leaving() {
    if (state == ShellPanel.inbox) {
      ref.read(inboxControllerProvider.notifier).panelClosed();
    }
  }
}

final shellPanelProvider =
    NotifierProvider.autoDispose<ShellPanelController, ShellPanel>(
        ShellPanelController.new);

/// La rotta della pagina-pannello nel layout stretto: `/friends`, `/inbox`,
/// `/recommend`, `/rate`.
String shellPanelRoute(ShellPanel panel) {
  assert(panel != ShellPanel.none);
  return '/${panel.name}';
}

/// Apre (o chiude, se è già aperto) [panel]: pannello laterale come oggi;
/// nel layout stretto pagina intera con la freccia indietro (spec 1c §4.2).
void openShellPanel(BuildContext context, WidgetRef ref, ShellPanel panel) {
  final panels = ref.read(shellPanelProvider.notifier);
  if (!FormFactor.of(context).compact) {
    panels.toggle(panel);
    return;
  }
  final open = ref.read(shellPanelProvider);
  // Uno alla volta: la pagina-pannello aperta si chiude ([ShellPanelPage]);
  // se era la stessa, basta così.
  panels.close();
  if (open != panel) unawaited(context.push(shellPanelRoute(panel)));
}

/// Pagina di un pannello nel layout stretto (sotto la barra, con la sua
/// freccia indietro). Apre [panel] e lo chiude uscendo, così ricarica degli
/// amici e letture delle notifiche vanno come col pannello laterale. Se il
/// pannello si chiude da un'altra parte (la X o un'azione del contenuto, il
/// player che si apre, la funzione sparita) la pagina se ne va.
class ShellPanelPage extends ConsumerStatefulWidget {
  const ShellPanelPage({super.key, required this.panel, required this.child});

  final ShellPanel panel;
  final Widget child;

  @override
  ConsumerState<ShellPanelPage> createState() => _ShellPanelPageState();
}

class _ShellPanelPageState extends ConsumerState<ShellPanelPage> {
  late final ShellPanelController _panels =
      ref.read(shellPanelProvider.notifier);
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    // Durante la costruzione non si cambia un provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panels.open(widget.panel);
    });
  }

  @override
  void dispose() {
    _disposing = true;
    // Dopo lo smontaggio (qui non si cambia un provider), e solo il proprio:
    // un'altra pagina-pannello può essere già aperta.
    final panels = _panels;
    final panel = widget.panel;
    scheduleMicrotask(() => panels.closeIfOpen(panel));
    super.dispose();
  }

  void _onPanel(ShellPanel? previous, ShellPanel next) {
    if (_disposing || previous != widget.panel || next == widget.panel) return;
    // Il navigatore della shell: col player aperto sopra, `context.pop`
    // chiuderebbe il player.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      // Aperta da un indirizzo, senza pagina sotto.
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(shellPanelProvider, _onPanel);
    return widget.child;
  }
}
