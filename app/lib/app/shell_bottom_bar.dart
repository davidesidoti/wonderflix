import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/auth/profiles_state.dart';
import '../features/auth/session_controller.dart';
import '../features/calendar/calendar_providers.dart';
import '../features/requests/requests_providers.dart';
import '../l10n/gen/app_localizations.dart';
import '../ui/form_factor.dart';
import 'theme.dart';

/// Altezza della barra in basso, senza l'area sicura.
const shellBottomBarHeight = 56.0;

/// Barra in basso del layout stretto (spec 1c §4.2): Home, Cerca, La mia
/// lista, Richieste (solo con Seerr) e Altro. Altro apre dal basso le voci
/// della barra in alto e del menu del profilo che qui non ci sono; la scelta
/// arriva a [onMenu] (una rotta come `/movies`, o una voce del menu del
/// profilo: `settings`, `admin`, `switch`, `add`, `logout`), che la esegue
/// con la shell: questa barra sparisce se la finestra si allarga col foglio
/// aperto.
class ShellBottomBar extends ConsumerWidget {
  const ShellBottomBar(
      {super.key, required this.location, required this.onMenu});

  final String location;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    Widget item(String route, String label, IconData icon, VoidCallback onTap) {
      final color =
          location.startsWith(route) ? WfColors.gold : WfColors.cream;
      return Expanded(
        child: InkWell(
          key: Key('bottom-nav-$route'),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
        ),
      );
    }

    return Material(
      color: WfColors.bg,
      shape: const Border(top: BorderSide(color: WfColors.border)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: shellBottomBarHeight,
          child: Row(
            children: [
              item('/home', l.navHome, LucideIcons.house,
                  () => context.go('/home')),
              item('/search', l.navSearch, LucideIcons.search,
                  () => context.go('/search')),
              item('/mylist', l.navMyList, LucideIcons.bookmark,
                  () => context.go('/mylist')),
              // Solo con le richieste con Seerr (spec I §9.4).
              if (ref.watch(requestsAvailableProvider))
                item('/requests', l.navRequests, LucideIcons.messageSquarePlus,
                    () => context.go('/requests')),
              item('/more', l.navMore, LucideIcons.ellipsis,
                  () => _showMore(context)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMore(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: WfColors.surface,
      showDragHandle: true,
      builder: (context) => const _MoreSheet(),
    );
    if (choice != null) onMenu(choice);
  }
}

/// Le voci di "Altro"; restituisce la scelta chiudendo il foglio.
class _MoreSheet extends ConsumerWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    final canAddProfile =
        !ref.watch(profilesProvider.select((p) => p.book.isFull));
    Widget entry(String value, String label, IconData icon) => ListTile(
          key: Key('more-$value'),
          minTileHeight: minTouchTarget,
          leading: Icon(icon, size: 20, color: WfColors.cream),
          title: Text(label),
          onTap: () => Navigator.of(context).pop(value),
        );
    // Scorre se non ci sta (telefono in orizzontale).
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        entry('/movies', l.navMovies, LucideIcons.film),
        entry('/series', l.navSeries, LucideIcons.tv),
        // Solo con il calendario del plugin (1.13.0).
        if (ref.watch(calendarAvailableProvider))
          entry('/calendar', l.navCalendar, LucideIcons.calendarDays),
        entry('settings', l.menuSettings, LucideIcons.settings),
        // Solo per gli admin di Jellyfin (spec J §7).
        if (user?.isAdministrator ?? false)
          entry('admin', l.menuAdmin, LucideIcons.shieldCheck),
        entry('switch', l.profilesSwitch, LucideIcons.users),
        // Al massimo 5 profili (spec K §9.5).
        if (canAddProfile)
          entry('add', l.profilesAdd, LucideIcons.userPlus),
        entry('logout', l.menuLogout, LucideIcons.logOut),
      ],
    );
  }
}
