import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/plugin_admin_models.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// Le funzioni della cassetta del plugin (spec J §9.6): lo stato delle
/// novità, riletto ogni 30 s, e le azioni annuncio, interruttore e "Invia
/// ora".
class InboxAdminController extends AdminTabController<NewTitlesStatus> {
  static const every = Duration(seconds: 30);

  @override
  Duration get interval => every;

  @override
  Future<NewTitlesStatus> fetch() =>
      ref.read(pluginAdminApiProvider).newTitles();

  /// A quante persone è arrivato. Un testo rifiutato dà un
  /// `ServerErrorException` con 400.
  Future<int> announce(String text) =>
      act(() => ref.read(pluginAdminApiProvider).announce(text));

  /// Accende o spegne la raccolta. Se la scrittura riesce, lo stato prende
  /// subito il valore scritto, prima della rilettura: se quella fallisce,
  /// l'interruttore non torna a un valore che sul server non c'è più.
  Future<void> setNotifyNewTitles(bool enabled) => act(() async {
        await ref.read(pluginAdminApiProvider).setNotifyNewTitles(enabled);
        // Pagina chiusa nel frattempo: lo stato non si legge più (Riverpod
        // lancia), e la scrittura è comunque riuscita.
        if (!ref.mounted) return;
        final current = state.value;
        if (current != null) {
          state = AdminData<NewTitlesStatus>(
            value: NewTitlesStatus(enabled: enabled, pending: current.pending),
            error: state.error,
            updatedAt: state.updatedAt,
          );
        }
      });

  Future<NewTitlesSent> sendNewTitles() =>
      act(() => ref.read(pluginAdminApiProvider).sendNewTitles());
}

final inboxAdminControllerProvider = NotifierProvider.autoDispose<
    InboxAdminController, AdminData<NewTitlesStatus>>(InboxAdminController.new);

/// La card Seerr: [status] `null` con un plugin più vecchio della 1.4.0, e
/// allora la card non c'è.
class SeerrCardData {
  const SeerrCardData(this.status);

  final SeerrAdminStatus? status;
}

/// Lo stato di Seerr nel plugin, riletto ogni 30 s, e "Prova collegamento".
class SeerrAdminController extends AdminTabController<SeerrCardData> {
  static const every = Duration(seconds: 30);

  @override
  Duration get interval => every;

  @override
  Future<SeerrCardData> fetch() async =>
      SeerrCardData(await ref.read(pluginAdminApiProvider).seerrStatus());

  Future<SeerrTestResult> test() =>
      act(() => ref.read(pluginAdminApiProvider).testSeerr());
}

final seerrAdminControllerProvider = NotifierProvider.autoDispose<
    SeerrAdminController, AdminData<SeerrCardData>>(SeerrAdminController.new);
