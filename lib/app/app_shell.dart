import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/auth_models.dart';
import '../features/auth/session_controller.dart';
import '../features/library/server_events_binding.dart';
import '../features/watch_party/watch_party_button.dart';
import '../features/watch_party/watch_party_invites.dart';
import '../l10n/gen/app_localizations.dart';
import '../ui/hover_builder.dart';
import 'back_navigation.dart';
import 'motion.dart';
import 'theme.dart';

/// Altezza della barra in alto.
const shellBarHeight = 64.0;

/// Struttura comune alle schermate autenticate: contenuto con la barra
/// superiore sovrapposta. Il contenuto occupa tutta la finestra; le pagine
/// che devono iniziare sotto la barra lasciano da sole il margine
/// (`shellPage`/`detailPage` con `underBar`), così la barra non sposta il
/// navigatore durante le transizioni.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// La pagina in cima è scorsa: la barra diventa scura e sfocata. Lo
  /// scrive la [ShellPageFrame] della pagina corrente.
  final _scrolled = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tiene aperto il WebSocket degli eventi finché si è autenticati.
    ref.watch(serverEventsBindingProvider);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: BackNavigationHandler(
        child: Stack(
          children: [
            Positioned.fill(
              child: _ShellScrolledScope(
                scrolled: _scrolled,
                child: widget.child,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: shellBarHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _BarBackground(scrolled: _scrolled),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const _BackButton(),
                        Image.asset('assets/brand/logo.png', height: 40),
                        const SizedBox(width: 32),
                        _NavBar(location: widget.location, items: [
                          (label: l.navHome, route: '/home', icon: null),
                          (label: l.navMovies, route: '/movies', icon: null),
                          (label: l.navSeries, route: '/series', icon: null),
                          (label: l.navMyList, route: '/mylist', icon: null),
                          (
                            label: l.navSearch,
                            route: '/search',
                            icon: LucideIcons.search
                          ),
                        ]),
                        const Spacer(),
                        const WatchPartyButton(),
                        const SizedBox(width: 16),
                        if (user != null) _UserMenu(user: user),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Invito a un watch party appena nato (spec B §5.8).
            const Positioned(top: 72, right: 24, child: WatchPartyInviteCard()),
          ],
        ),
      ),
    );
  }
}

/// Sfondo della barra: velo in cima finché la pagina è in alto, scuro e
/// sfocato quando è scorsa.
class _BarBackground extends StatelessWidget {
  const _BarBackground({required this.scrolled});

  final ValueNotifier<bool> scrolled;

  @override
  Widget build(BuildContext context) {
    final fade = WfMotion.of(context).duration(WfMotion.medium);
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      builder: (context, scrolled, _) => Stack(
        fit: StackFit.expand,
        children: [
          // Velo in cima per leggere la barra sulle pagine a tutta
          // altezza; sulle altre è sfondo su sfondo.
          AnimatedOpacity(
            opacity: scrolled ? 0 : 1,
            duration: fade,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB30A0A0A), Color(0x000A0A0A)],
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            key: const Key('shell-bar-backdrop'),
            opacity: scrolled ? 1 : 0,
            duration: fade,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: const ColoredBox(color: Color(0xBF0A0A0A)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Porta alle pagine della shell il valore "pagina scorsa" della barra.
class _ShellScrolledScope extends InheritedWidget {
  const _ShellScrolledScope({required this.scrolled, required super.child});

  final ValueNotifier<bool> scrolled;

  @override
  bool updateShouldNotify(_ShellScrolledScope oldWidget) =>
      oldWidget.scrolled != scrolled;
}

/// Contenuto di una pagina della shell (lo aggiungono `shellPage` e
/// `detailPage`). Lascia il margine sotto la barra se [underBar]; altrimenti
/// la pagina arriva al bordo della finestra (Home e scheda, spec C §11.1).
///
/// Ricorda se la propria pagina è scorsa e, quando la sua rotta è in cima,
/// lo dice alla barra: tornando indietro la barra ritrova lo stato della
/// pagina, e una pagina nuova parte chiara.
class ShellPageFrame extends StatefulWidget {
  const ShellPageFrame(
      {super.key, required this.underBar, required this.child});

  final bool underBar;
  final Widget child;

  @override
  State<ShellPageFrame> createState() => _ShellPageFrameState();
}

class _ShellPageFrameState extends State<ShellPageFrame> {
  ValueNotifier<bool>? _barScrolled;
  bool _scrolled = false;
  bool _current = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _barScrolled = context
        .getInheritedWidgetOfExactType<_ShellScrolledScope>()
        ?.scrolled;
    // Dipende dalla rotta: si riesegue quando torna in cima.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    final becameCurrent = current && !_current;
    _current = current;
    if (becameCurrent) _publish();
  }

  bool _onScroll(ScrollNotification notification) {
    // Solo lo scroll verticale della pagina, non le righe orizzontali.
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      final scrolled = notification.metrics.pixels > 4;
      if (scrolled != _scrolled) {
        _scrolled = scrolled;
        if (_current) _publish();
      }
    }
    return false;
  }

  /// Scrive lo stato nella barra; durante la costruzione (la shell è un
  /// antenato) aspetta la fine del fotogramma.
  void _publish() {
    void write() {
      if (mounted && _current) _barScrolled?.value = _scrolled;
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => write());
    } else {
      write();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: widget.underBar ? shellBarHeight : 0),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
      );
}

typedef _NavEntry = ({String label, String route, IconData? icon});

/// Voci della barra con un'unica sottolineatura oro che scorre sotto
/// quella attiva (spec C §11.1).
class _NavBar extends StatefulWidget {
  const _NavBar({required this.location, required this.items});

  final String location;
  final List<_NavEntry> items;

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> {
  final _stackKey = GlobalKey();
  final _itemKeys = <String, GlobalKey>{};

  /// Posizione della voce attiva nella barra; `null` = nessuna.
  Rect? _active;

  /// Ultima posizione nota, per far sparire la linea dov'era.
  Rect? _last;

  String? get _activeRoute {
    for (final item in widget.items) {
      if (widget.location.startsWith(item.route)) return item.route;
    }
    return null;
  }

  void _measure() {
    if (!mounted) return;
    final route = _activeRoute;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final box = route == null
        ? null
        : _itemKeys[route]?.currentContext?.findRenderObject() as RenderBox?;
    Rect? rect;
    if (stack != null && box != null && box.hasSize) {
      final offset = box.localToGlobal(Offset.zero, ancestor: stack);
      rect = offset & box.size;
    }
    if (rect != _active) {
      setState(() {
        _active = rect;
        if (rect != null) _last = rect;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final shown = _active ?? _last;
    return Stack(
      key: _stackKey,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in widget.items) ...[
              KeyedSubtree(
                key: Key('nav-${item.route}'),
                child: _NavItem(
                  key: _itemKeys.putIfAbsent(item.route, GlobalKey.new),
                  label: item.label,
                  icon: item.icon,
                  active: widget.location.startsWith(item.route),
                  onTap: () => context.go(item.route),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
        if (shown != null)
          AnimatedPositioned(
            key: const Key('nav-indicator'),
            left: shown.left,
            width: shown.width,
            top: shown.bottom - 2,
            height: 2,
            duration: motion.pick(full: WfMotion.medium, reduced: Duration.zero),
            curve: WfMotion.emphasized,
            child: AnimatedOpacity(
              opacity: _active == null ? 0 : 1,
              duration: WfMotion.fast,
              child: const ColoredBox(color: WfColors.gold),
            ),
          ),
      ],
    );
  }
}

/// Freccia "indietro" accanto al logo; occupa sempre lo stesso spazio così il
/// logo non si sposta, ma compare solo se c'è una pagina a cui tornare.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return const SizedBox(width: 48);
    // Si ricostruisce a ogni push/pop, anche dentro la stessa ShellRoute.
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => SizedBox(
        width: 48,
        child: router.canPop()
            ? IconButton(
                tooltip: AppLocalizations.of(context).navBack,
                onPressed: router.pop,
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.hovered)
                          ? WfColors.gold
                          : WfColors.cream),
                ),
                icon: const Icon(LucideIcons.arrowLeft),
              )
            : null,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final symbol = icon;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        final color = active || hovered ? WfColors.gold : WfColors.cream;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (symbol != null) ...[
                  Icon(symbol, size: 16, color: color),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.user});

  final JellyfinUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final initial = user.name.isEmpty ? '?' : user.name[0].toUpperCase();
    return PopupMenuButton<String>(
      key: const Key('user-menu'),
      tooltip: user.name,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'settings':
            context.go('/settings');
          case 'logout':
            unawaited(ref.read(sessionControllerProvider.notifier).logout());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              const Icon(LucideIcons.settings, size: 18, color: WfColors.cream),
              const SizedBox(width: 12),
              Text(l.menuSettings),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: WfColors.cream),
              const SizedBox(width: 12),
              Text(l.menuLogout),
            ],
          ),
        ),
      ],
      child: HoverBuilder(
        builder: (context, hovered) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: WfColors.gold,
              child: Text(initial,
                  style: const TextStyle(
                      color: WfColors.bg, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(user.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: hovered ? WfColors.gold : WfColors.cream)),
            ),
          ],
        ),
      ),
    );
  }
}
