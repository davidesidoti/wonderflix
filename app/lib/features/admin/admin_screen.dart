import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/states.dart';
import '../auth/session_controller.dart';
import '../downloads/downloads_tab.dart';
import '../space/space_tab.dart';
import '../social/social_providers.dart';
import 'activity_tab.dart';
import 'admin_counts.dart';
import 'admin_navigation.dart';
import 'admin_providers.dart';
import 'admin_rail.dart';
import 'admin_widgets.dart';
import 'maintenance_tab.dart';
import 'restart_controller.dart';
import 'server_info_controller.dart';
import 'server_strip.dart';
import 'sessions_tab.dart';
import 'users_tab.dart';
import 'wonderflix_controllers.dart';
import 'wonderflix_tab.dart';

/// La pagina Amministrazione (spec J §7, §9.1): il blocco del server, le
/// schede e il contenuto della scheda scelta. La scheda sta nell'indirizzo;
/// cambiandola la pagina resta la stessa (con la striscia e un riavvio in
/// corso). Chi non è admin torna alla Home; chi smette di esserlo mentre la
/// guarda riceve anche un avviso.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key, this.tab = AdminTab.sessions});

  final AdminTab tab;

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  static const _homeRoute = '/home';

  /// La pagina è stata vista da admin: se smette di esserlo, l'avviso.
  bool _wasAdmin = false;

  /// Già partita verso la Home: ci va una volta sola.
  bool _leaving = false;

  bool get _signedIn => ref.read(sessionControllerProvider) is SessionSignedIn;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!ref.watch(isAdminProvider)) {
      // Senza sessione (uscita, 401) non è che si perdano i permessi: il
      // router porta al Login, e durante la transizione questa pagina resta
      // montata. Niente avviso e niente Home.
      if (!_signedIn) return const SizedBox.shrink();
      if (!_leaving) {
        _leaving = true;
        final lost = _wasAdmin;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_signedIn) return;
          if (lost) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l.adminNoLongerAdmin)));
          }
          context.go(_homeRoute);
        });
      }
      return const SizedBox.shrink();
    }
    _wasAdmin = true;
    // Nello stretto la striscia è un figlio della lista e si smonta scorrendo:
    // senza ascoltatori i due provider (autoDispose) morirebbero con lei,
    // perdendo il riavvio in corso. La pagina li tiene vivi.
    ref.listen(restartControllerProvider, (_, _) {});
    ref.listen(serverInfoControllerProvider, (_, _) {});
    // Idem per i numeri sulle voci: le voci si smontano, i contatori no.
    ref.listen(adminCountsProvider, (_, _) {});
    // E l'esito delle prove di Sonarr/Radarr e Seerr, che la card scrive e la
    // spia legge: chiudere la card non lo perde.
    ref.listen(arrTestResultProvider, (_, _) {});
    ref.listen(seerrTestResultProvider, (_, _) {});
    // Le schede del plugin (Utenti e WonderFlix) ci sono solo con le sue
    // funzioni; se una manca ed è nell'indirizzo (o la funzione sparisce
    // mentre la si guarda), si mostra Sessioni. Ma finché non si sa se il
    // plugin c'è (subito dopo il login) non si può dire che manchi: si
    // aspetta, senza passare da Sessioni, che si rileggerebbe per niente e
    // farebbe un lampo di contenuto sbagliato.
    final features = ref.watch(socialAvailabilityProvider.select(
        (f) => (
          inbox: f.inbox,
          account: f.account,
          downloads: f.downloads,
          space: f.space,
          known: f.known,
        )));
    final tabs = adminTabs(
        inbox: features.inbox,
        account: features.account,
        downloads: features.downloads,
        space: features.space);
    final waitingForPlugin = !features.known && !tabs.contains(widget.tab);
    final tab = tabs.contains(widget.tab) || waitingForPlugin
        ? widget.tab
        : AdminTab.sessions;
    final compact = FormFactor.of(context).compact;
    // Nello stretto il blocco del server e la fila delle schede scorrono con
    // la scheda (spec "Struttura della pagina"): ogni scheda li mette in cima
    // al suo elenco, così Riavvia resta raggiungibile anche con la scheda in
    // errore. Nel largo stanno nella colonna.
    final Widget? header = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ServerStrip(),
              const SizedBox(height: 12),
              AdminTabStrip(tabs: tabs, current: tab),
            ],
          )
        : null;
    final Widget content = waitingForPlugin
        ? (header == null
            ? const LoadingView()
            : adminTabState(context, header, const LoadingView()))
        : switch (tab) {
            AdminTab.sessions => SessionsTab(header: header),
            AdminTab.users => UsersTab(header: header),
            AdminTab.maintenance => MaintenanceTab(header: header),
            AdminTab.activity => ActivityTab(header: header),
            AdminTab.downloads => DownloadsTab(header: header),
            AdminTab.space => SpaceTab(header: header),
            AdminTab.wonderflix => WonderflixTab(header: header),
          };
    if (compact) return content;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminRail(tabs: tabs, current: tab),
        Expanded(child: content),
      ],
    );
  }
}
