import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../library/library_providers.dart';

final userConfigApiProvider =
    Provider<UserConfigApi>((ref) => UserConfigApi(ref.watch(jellyfinHttpProvider)));

/// Lingue di riproduzione dell'utente, salvate sul server.
class LanguagePreferencesController extends AsyncNotifier<LanguagePreferences> {
  /// Configurazione completa letta dal server: si rimanda tutta.
  Map<String, dynamic> _configuration = const {};

  @override
  Future<LanguagePreferences> build() async {
    _configuration = await ref.watch(userConfigApiProvider).configuration();
    return LanguagePreferences.fromConfiguration(_configuration);
  }

  /// Aggiorna subito la schermata; se il server rifiuta, torna al valore di
  /// prima e rilancia l'errore.
  Future<void> save(LanguagePreferences next) async {
    final previous = state.value;
    state = AsyncData(next);
    try {
      final updated = next.applyTo(_configuration);
      await ref
          .read(userConfigApiProvider)
          .saveConfiguration(ref.read(currentUserIdProvider), updated);
      _configuration = updated;
    } on Object {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

final languagePreferencesProvider = AsyncNotifierProvider.autoDispose<
    LanguagePreferencesController,
    LanguagePreferences>(LanguagePreferencesController.new);
