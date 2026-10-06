import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/auth_models.dart';
import '../features/admin/admin_navigation.dart';
import '../features/auth/session_controller.dart';
import '../features/friends/friend_request_card.dart';
import '../features/friends/friends_button.dart';
import '../features/friends/friends_panel.dart';
import '../features/inbox/inbox_button.dart';
import '../features/library/server_events_binding.dart';
import '../features/requests/requests_providers.dart';
import '../features/watch_party/watch_party_button.dart';
import '../features/watch_party/watch_party_invites.dart';
import '../l10n/gen/app_localizations.dart';
import '../ui/hover_builder.dart';
import '../ui/sliding_underline.dart';
import '../ui/wf_menus.dart';
import 'back_navigation.dart';
import 'motion.dart';
import 'theme.dart';

part 'shell_header.dart';

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
                          // Solo con le richieste con Seerr (spec I §9.4).
                          if (ref.watch(requestsAvailableProvider))
                            (label: l.navRequests, route: '/requests', icon: null),
                          (
                            label: l.navSearch,
                            route: '/search',
                            icon: LucideIcons.search
                          ),
                        ]),
                        const SizedBox(width: 24),
                        // Tutto lo spazio libero va al titolo: il pulsante
                        // non viene schiacciato da uno Spacer.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _BarTitle(header: _header),
                          ),
                        ),
                        const WatchPartyButton(),
                        const FriendsButton(),
                        const InboxButton(),
                        const SizedBox(width: 16),
                        if (user != null) _UserMenu(user: user),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Invito a un watch party appena nato (spec B §5.8) e richiesta
            // di amicizia appena arrivata (spec F §8.4), una sotto l'altra.
            const Positioned(
              top: 72,
              right: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: 8,
                children: [WatchPartyInviteCard(), FriendRequestCard()],
              ),
            ),
            // Pannello Amici, sopra la barra e le schede (spec F §8.3).
            const Positioned.fill(child: FriendsPanelHost()),
            // Pannello Notifiche, sopra la barra e le schede (spec G §7.5).
            const Positioned.fill(child: InboxPanelHost()),
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
      popUpAnimationStyle: wfPopUpAnimation(context),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            context.go('/settings');
          case 'admin':
            openAdmin(context);
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
        // Solo per gli admin di Jellyfin (spec J §7).
        if (user.isAdministrator)
          PopupMenuItem(
            value: 'admin',
            child: Row(
              children: [
                const Icon(LucideIcons.shieldCheck,
                    size: 18, color: WfColors.cream),
                const SizedBox(width: 12),
                Text(l.menuAdmin),
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
