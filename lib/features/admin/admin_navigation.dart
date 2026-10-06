import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';

/// Le schede della pagina Amministrazione (spec J §9). Il piano 16b
/// aggiunge Manutenzione, Registro e WonderFlix.
enum AdminTab {
  sessions;

  /// Dal parametro `tab` dell'indirizzo: senza, o con un valore
  /// sconosciuto, Sessioni.
  static AdminTab parse(String? raw) =>
      values.firstWhere((tab) => tab.name == raw, orElse: () => sessions);
}

String adminTabLabel(AppLocalizations l, AdminTab tab) => switch (tab) {
      AdminTab.sessions => l.adminTabSessions,
    };

/// Apre la pagina Amministrazione, sulla scheda [tab] se c'è.
void openAdmin(BuildContext context, {AdminTab? tab}) =>
    context.go(tab == null ? '/admin' : '/admin?tab=${tab.name}');
