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

  Future<void> setNotifyNewTitles(bool enabled) =>
      act(() => ref.read(pluginAdminApiProvider).setNotifyNewTitles(enabled));

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
