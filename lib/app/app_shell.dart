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
import '../ui/sliding_underline.dart';
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

  /// Titolo e azione della pagina in cima, se la sua testata è uscita.
  /// Anche questo lo scrive la [ShellPageFrame] della pagina corrente.
  final _header = ValueNotifier<ShellHeader?>(null);

  @override
  void dispose() {
    _scrolled.dispose();
    _header.dispose();
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
              child: _ShellBarScope(
                scrolled: _scrolled,
                header: _header,
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
                        const SizedBox(width: 24),
                        _BarTitle(header: _header),
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
/// sfocato quando è scorsa. Solo decorazione: il mouse (rotella compresa)
/// passa alla pagina sotto.
class _BarBackground extends StatelessWidget {
  const _BarBackground({required this.scrolled});

  final ValueNotifier<bool> scrolled;

  @override
  Widget build(BuildContext context) {
    final fade = WfMotion.of(context).duration(WfMotion.medium);
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: scrolled,
        builder: (context, scrolled, _) => Stack(
          fit: StackFit.expand,
          children: [
            // Velo in cima per leggere la barra sulle pagine a tutta
            // altezza; sulle altre è sfondo su sfondo.
            AnimatedOpacity(
              opacity: scrolled ? 0 : 1,
              duration: fade,
              curve: WfMotion.standard,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      WfColors.bg.withValues(alpha: 0.7),
                      WfColors.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              key: const Key('shell-bar-backdrop'),
              opacity: scrolled ? 1 : 0,
              duration: fade,
              curve: WfMotion.standard,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: ColoredBox(color: WfColors.bg.withValues(alpha: 0.75)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Porta alle pagine della shell i valori della barra: "pagina scorsa" e
/// titolo della pagina.
class _ShellBarScope extends InheritedWidget {
  const _ShellBarScope({
    required this.scrolled,
    required this.header,
    required super.child,
  });

  final ValueNotifier<bool> scrolled;
  final ValueNotifier<ShellHeader?> header;

  @override
  bool updateShouldNotify(_ShellBarScope oldWidget) =>
      oldWidget.scrolled != scrolled || oldWidget.header != header;
}

/// Titolo e azione della pagina mostrati nella barra quando la sua testata
/// è uscita dallo schermo (spec C §9.2).
@immutable
class ShellHeader {
  const ShellHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  // L'uguaglianza ignora il callback: cambia a ogni build.
  @override
  bool operator ==(Object other) =>
      other is ShellHeader &&
      other.title == title &&
      other.actionLabel == actionLabel;

  @override
  int get hashCode => Object.hash(title, actionLabel);
}

/// Contenuto di una pagina della shell (lo aggiungono `shellPage` e
/// `detailPage`). Lascia il margine sotto la barra se [underBar]; altrimenti
/// la pagina arriva al bordo della finestra (Home e scheda, spec C §11.1).
///
/// Ricorda se la propria pagina è scorsa e il suo titolo per la barra
/// ([ShellHeaderPublisher]) e, quando la sua rotta è in cima, li dice alla
/// barra: tornando indietro la barra ritrova lo stato e il titolo della
/// pagina, e una pagina nuova parte chiara e senza titolo.
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
  ValueNotifier<ShellHeader?>? _barHeader;
  bool _scrolled = false;
  ShellHeader? _pageHeader;
  bool _current = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.getInheritedWidgetOfExactType<_ShellBarScope>();
    _barScrolled = scope?.scrolled;
    _barHeader = scope?.header;
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

  void _setHeader(ShellHeader? header) {
    _pageHeader = header;
    if (_current) _publish();
  }

  /// Scrive stato e titolo nella barra; durante la costruzione (la shell è
  /// un antenato) aspetta la fine del fotogramma.
  void _publish() {
    void write() {
      if (!mounted || !_current) return;
      _barScrolled?.value = _scrolled;
      _barHeader?.value = _pageHeader;
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

/// Pubblica [header] nella barra quando lo scroll di [controller] supera
/// [threshold], e lo toglie sotto la soglia o alla chiusura.
class ShellHeaderPublisher extends StatefulWidget {
  const ShellHeaderPublisher({
    super.key,
    required this.controller,
    required this.threshold,
    required this.header,
    required this.child,
  });

  final ScrollController controller;
  final double threshold;

  /// `null` finché non si sa cosa mostrare.
  final ShellHeader? header;
  final Widget child;

  @override
  State<ShellHeaderPublisher> createState() => _ShellHeaderPublisherState();
}

class _ShellHeaderPublisherState extends State<ShellHeaderPublisher> {
  _ShellPageFrameState? _frame;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frame = context.findAncestorStateOfType<_ShellPageFrameState>();
  }

  @override
  void didUpdateWidget(ShellHeaderPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    if (_shown && oldWidget.header != widget.header) {
      _frame?._setHeader(widget.header);
    }
  }

  void _onScroll() {
    final controller = widget.controller;
    final shown =
        controller.hasClients && controller.offset >= widget.threshold;
    if (shown == _shown) return;
    _shown = shown;
    _frame?._setHeader(shown ? widget.header : null);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    if (_shown) _frame?._setHeader(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Titolo e piccolo "Riproduci" della pagina in cima (spec C §9.2).
class _BarTitle extends StatelessWidget {
  const _BarTitle({required this.header});

  final ValueNotifier<ShellHeader?> header;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    return Flexible(
      child: ValueListenableBuilder<ShellHeader?>(
        valueListenable: header,
        builder: (context, value, _) => AnimatedSwitcher(
          duration: motion.duration(WfMotion.medium),
          switchInCurve: WfMotion.emphasized,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                  .animate(animation),
              child: child,
            ),
          ),
          child: value == null
              ? const SizedBox.shrink()
              : Row(
                  key: const Key('shell-bar-title'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(value.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WfText.display(22)),
                    ),
                    if (value.onAction != null) ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        key: const Key('shell-bar-play'),
                        onPressed: value.onAction,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(LucideIcons.play, size: 14),
                        label: Text(value.actionLabel ?? ''),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
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
  final _itemKeys = <Object, GlobalKey>{};

  String? get _activeRoute {
    for (final item in widget.items) {
      if (widget.location.startsWith(item.route)) return item.route;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // La linea si rimisura da sola se cambia la dimensione del testo.
    return SlidingUnderline(
      selected: _activeRoute,
      itemKeys: _itemKeys,
      indicatorKey: const Key('nav-indicator'),
      child: Row(
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
