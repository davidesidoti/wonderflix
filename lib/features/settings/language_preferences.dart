import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../library/library_providers.dart';

final userConfigApiProvider =
    Provider<UserConfigApi>((ref) => UserConfigApi(ref.watch(jellyfinHttpProvider)));

/// Lingue di riproduzione dell'utente, salvate sul server.
class LanguagePreferencesController extends AsyncNotifier<LanguagePreferences> {
  /// Ultime preferenze confermate dal server (lette o salvate).
  LanguagePreferences? _saved;

  /// Coda dei salvataggi: uno alla volta, nell'ordine delle scelte.
  Future<void> _queue = Future.value();

  @override
  Future<LanguagePreferences> build() async {
    final config = await ref.watch(userConfigApiProvider).configuration();
    return _saved = LanguagePreferences.fromConfiguration(config);
  }

  /// Aggiorna subito la schermata e salva sul server dopo i salvataggi
  /// precedenti. Se il server rifiuta rilancia l'errore e, se nel frattempo
  /// non è stato scelto altro, torna all'ultimo valore salvato.
  Future<void> save(LanguagePreferences next) {
    final api = ref.read(userConfigApiProvider);
    final userId = ref.read(currentUserIdProvider);
    state = AsyncData(next);
    final run = _queue.then((_) => _send(api, userId, next));
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _send(
      UserConfigApi api, String userId, LanguagePreferences next) async {
    try {
      // Il server sostituisce tutta la configurazione: si parte da quella
      // attuale, così non si perdono modifiche fatte altrove nel frattempo.
      final current = await api.configuration();
      await api.saveConfiguration(userId, next.applyTo(current));
      _saved = next;
    } on Object {
      final saved = _saved;
      if (ref.mounted && identical(state.value, next) && saved != null) {
        state = AsyncData(saved);
      }
      rethrow;
    }
  }
}

final languagePreferencesProvider = AsyncNotifierProvider.autoDispose<
    LanguagePreferencesController,
    LanguagePreferences>(LanguagePreferencesController.new);
