import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/notifications_api.dart';
import '../../core/social/notifications_models.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';

final notificationsApiProvider = Provider<NotificationsApi>(
  (ref) => NotificationsApi(ref.watch(jellyfinHttpProvider)),
);

/// Quali notifiche vuole l'utente aperto (spec V §4.2): stanno nel plugin,
/// si rileggono a ogni cambio di profilo. Senza la funzione `push` (o senza
/// utente) il plugin non ha l'endpoint: l'elenco è vuoto e non si chiede
/// niente; se la funzione arriva dopo, si legge allora.
class NotificationPrefsController extends AsyncNotifier<NotificationsInfo> {
  /// Cresce a ogni `build`: un salvataggio partito per un utente precedente
  /// non tocca lo stato di quello nuovo.
  int _generation = 0;

  /// L'ultimo valore noto del plugin per tipo: a cui tornare se un
  /// salvataggio fallisce, anche con due tocchi di fila sullo stesso tipo.
  final _confirmed = <String, bool>{};

  @override
  Future<NotificationsInfo> build() {
    _generation++;
    _confirmed.clear();
    final userId = ref.watch(
      sessionControllerProvider.select(
        (s) => s is SessionSignedIn ? s.user.id : null,
      ),
    );
    final push = ref.watch(socialAvailabilityProvider.select((f) => f.push));
    if (userId == null || !push) {
      return Future.value(
        const NotificationsInfo(vapidPublicKey: '', types: []),
      );
    }
    return ref.watch(notificationsApiProvider).get();
  }

  /// Vero finché le preferenze non sono caricate o il tipo non c'è: come il
  /// plugin, che manda tutto a chi non ha scelto. Mentre si rileggono (dopo
  /// un cambio di profilo Riverpod tiene il valore precedente) sono quelle
  /// di un altro utente: non valgono.
  bool isEnabled(String type) {
    if (state.isLoading) return true;
    for (final pref in state.value?.types ?? const <NotificationTypePref>[]) {
      if (pref.type == type) return pref.enabled;
    }
    return true;
  }

  /// Salva subito; non riuscito, il tipo torna com'era e risponde `false`.
  Future<bool> setEnabled(String type, bool enabled) async {
    final generation = _generation;
    final saved = _confirmed[type] ??= isEnabled(type);
    _put(type, enabled);
    try {
      await ref.read(notificationsApiProvider).setEnabled(type, enabled);
      if (generation == _generation) _confirmed[type] = enabled;
      return true;
    } on ApiException {
      // Solo se è ancora il valore di questo tocco: se ce n'è stato un
      // altro, decide lui.
      if (ref.mounted &&
          generation == _generation &&
          isEnabled(type) == enabled) {
        _put(type, saved);
      }
      return false;
    }
  }

  /// Cambia solo [type]: due interruttori toccati di fila non si disfano a
  /// vicenda.
  void _put(String type, bool enabled) {
    final info = state.value;
    if (info == null) return;
    state = AsyncData(
      NotificationsInfo(
        vapidPublicKey: info.vapidPublicKey,
        types: [
          for (final pref in info.types)
            if (pref.type == type)
              NotificationTypePref(type: type, enabled: enabled)
            else
              pref,
        ],
      ),
    );
  }
}

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsController, NotificationsInfo>(
      NotificationPrefsController.new,
    );
