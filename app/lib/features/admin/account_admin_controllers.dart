import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/social/account_models.dart';
import '../../core/social/plugin_admin_models.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// La scheda Utenti (spec L §9.5): gli utenti con i loro contatti per il
/// recupero e le azioni dell'admin. Si rilegge all'apertura della scheda,
/// dopo ogni azione e ogni [every].
class AccountUsersController
    extends AdminTabController<List<AdminAccountUser>> {
  /// L'elenco cambia di rado: basta una lettura ogni tanto (l'infrastruttura
  /// delle schede vuole un intervallo, decisione 2 del piano 18c).
  static const every = Duration(minutes: 2);

  @override
  Duration get interval => every;

  @override
  Future<List<AdminAccountUser>> fetch() =>
      ref.read(pluginAdminApiProvider).accountUsers();

  /// Manda all'utente il codice di recupero: i canali dove è arrivato.
  Future<List<AccountChannel>> sendRecoveryCode(String userId,
          {required String language}) =>
      act(() => ref
          .read(pluginAdminApiProvider)
          .sendRecoveryCode(userId, language: language));

  Future<void> unlinkContacts(String userId) =>
      act(() => ref.read(pluginAdminApiProvider).unlinkContacts(userId));

  /// "Imposta password": Jellyfin, senza la password attuale; chiude le
  /// sessioni dell'utente.
  Future<void> setPassword(String userId, String password) => act(() =>
      ref.read(authApiProvider).changePassword(userId, newPassword: password));
}

final accountUsersControllerProvider = NotifierProvider.autoDispose<
    AccountUsersController,
    AdminData<List<AdminAccountUser>>>(AccountUsersController.new);

/// La card "Recupero password" (spec L §9.6): lo stato dei canali, riletto
/// ogni 30 s, e "Invia prova a me".
class AccountAdminController extends AdminTabController<AccountAdminStatus> {
  static const every = Duration(seconds: 30);

  @override
  Duration get interval => every;

  @override
  Future<AccountAdminStatus> fetch() =>
      ref.read(pluginAdminApiProvider).accountStatus();

  /// La prova va ai contatti dell'admin.
  Future<AccountTestResult> test({required String language}) => act(() =>
      ref.read(pluginAdminApiProvider).testAccountChannels(language: language));
}

final accountAdminControllerProvider = NotifierProvider.autoDispose<
    AccountAdminController,
    AdminData<AccountAdminStatus>>(AccountAdminController.new);
