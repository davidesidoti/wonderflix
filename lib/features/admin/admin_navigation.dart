import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';

/// Le schede della pagina Amministrazione (spec J §9, spec L §9.5).
enum AdminTab {
  sessions,
  users,
  maintenance,
  activity,
  wonderflix;

  /// Dal parametro `tab` dell'indirizzo: senza, o con un valore
  /// sconosciuto, Sessioni.
  static AdminTab parse(String? raw) =>
      values.firstWhere((tab) => tab.name == raw, orElse: () => sessions);
}

/// Le schede da mostrare: Utenti solo con i contatti per il recupero del
/// plugin (`account`, spec L §9.5), WonderFlix solo con la cassetta
/// (`inbox`, spec J §7).
List<AdminTab> adminTabs({required bool inbox, required bool account}) => [
      for (final tab in AdminTab.values)
        if ((tab != AdminTab.wonderflix || inbox) &&
            (tab != AdminTab.users || account))
          tab,
    ];

String adminTabLabel(AppLocalizations l, AdminTab tab) => switch (tab) {
      AdminTab.sessions => l.adminTabSessions,
      AdminTab.users => l.adminTabUsers,
      AdminTab.maintenance => l.adminTabMaintenance,
      AdminTab.activity => l.adminTabActivity,
      AdminTab.wonderflix => l.adminTabWonderflix,
    };

/// Apre la pagina Amministrazione, sulla scheda [tab] se c'è.
void openAdmin(BuildContext context, {AdminTab? tab}) =>
    context.go(tab == null ? '/admin' : '/admin?tab=${tab.name}');
