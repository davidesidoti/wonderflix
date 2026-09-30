import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/auth_models.dart';
import '../features/auth/session_controller.dart';
import '../features/library/server_events_binding.dart';
import '../features/watch_party/watch_party_button.dart';
import '../features/watch_party/watch_party_invites.dart';
import '../l10n/gen/app_localizations.dart';
import 'back_navigation.dart';
import 'theme.dart';

/// Struttura comune alle schermate autenticate: barra superiore + contenuto.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tiene aperto il WebSocket degli eventi finché si è autenticati.
    ref.watch(serverEventsBindingProvider);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    final l = AppLocalizations.of(context);

    Widget nav(String label, String route, {IconData? icon}) => _NavItem(
          label: label,
          icon: icon,
          active: location.startsWith(route),
          onTap: () => context.go(route),
        );

    return Scaffold(
      body: BackNavigationHandler(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const _BackButton(),
                      Image.asset('assets/brand/logo.png', height: 40),
                      const SizedBox(width: 32),
                      nav(l.navHome, '/home'),
                      nav(l.navMovies, '/movies'),
                      nav(l.navSeries, '/series'),
                      nav(l.navMyList, '/mylist'),
                      nav(l.navSearch, '/search', icon: LucideIcons.search),
                      const Spacer(),
                      const WatchPartyButton(),
                      const SizedBox(width: 16),
                      if (user != null) _UserMenu(user: user),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
            // Invito a un watch party appena nato (spec B §5.8).
            const Positioned(top: 72, right: 24, child: WatchPartyInviteCard()),
          ],
        ),
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
                icon: const Icon(LucideIcons.arrowLeft, color: WfColors.cream),
              )
            : null,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
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
    final color = active ? WfColors.gold : WfColors.cream;
    final symbol = icon;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: active ? WfColors.gold : Colors.transparent, width: 2),
            ),
          ),
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
      ),
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
      child: Row(
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
          Flexible(child: Text(user.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
