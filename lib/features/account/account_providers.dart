import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';

/// Sul client principale: nell'accesso non ha token (`prepareLogin`), e
/// così partono le chiamate del recupero.
final accountApiProvider =
    Provider<AccountApi>((ref) => AccountApi(ref.watch(jellyfinHttpProvider)));

/// Il plugin ha i contatti per il recupero (spec L §9.1). Senza, Impostazioni
/// → Account ha solo il cambio della password.
final accountAvailableProvider = Provider<bool>((ref) =>
    ref.watch(socialAvailabilityProvider.select((f) => f.account)));

/// I contatti dell'utente aperto; `null` senza la funzione `account` o
/// senza un utente. Si rileggono ogni volta che la sezione torna a vedersi
/// (`autoDispose`) e a ogni cambio di profilo.
class AccountContactsController extends AsyncNotifier<AccountContacts?> {
  @override
  Future<AccountContacts?> build() async {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (userId == null || !ref.watch(accountAvailableProvider)) return null;
    return ref.watch(accountApiProvider).contacts();
  }

  /// I contatti dati da `Confirm`, senza rileggerli.
  void replace(AccountContacts contacts) => state = AsyncData(contacts);

  /// Di nuovo dal plugin (dopo uno scollegamento). Intanto restano quelli
  /// di prima, senza spinner.
  Future<void> reload() async {
    final result = await AsyncValue.guard(
        () => ref.read(accountApiProvider).contacts());
    if (ref.mounted) state = result;
  }
}

final accountContactsProvider = AsyncNotifierProvider.autoDispose<
    AccountContactsController, AccountContacts?>(AccountContactsController.new);
