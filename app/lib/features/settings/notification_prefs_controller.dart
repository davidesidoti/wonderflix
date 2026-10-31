import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/notifications_api.dart';
import '../../core/social/notifications_models.dart';
import '../auth/session_controller.dart';

final notificationsApiProvider = Provider<NotificationsApi>(
    (ref) => NotificationsApi(ref.watch(jellyfinHttpProvider)));

/// Quali notifiche vuole l'utente aperto (spec V §4.2): stanno nel plugin,
/// si rileggono a ogni cambio di profilo. Chi le legge controlla prima la
/// funzione `push`: senza, il plugin non ha l'endpoint.
class NotificationPrefsController extends AsyncNotifier<NotificationsInfo> {
  @override
  Future<NotificationsInfo> build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return ref.watch(notificationsApiProvider).get();
  }

  /// Vero finché le preferenze non sono caricate o il tipo non c'è: come il
  /// plugin, che manda tutto a chi non ha scelto.
  bool isEnabled(String type) {
    for (final pref in state.value?.types ?? const <NotificationTypePref>[]) {
      if (pref.type == type) return pref.enabled;
    }
    return true;
  }

  /// Salva subito; non riuscito, il tipo torna com'era e risponde `false`.
  Future<bool> setEnabled(String type, bool enabled) async {
    final previous = isEnabled(type);
    _put(type, enabled);
    try {
      await ref.read(notificationsApiProvider).setEnabled(type, enabled);
      return true;
    } on ApiException {
      if (ref.mounted) _put(type, previous);
      return false;
    }
  }

  /// Cambia solo [type]: due interruttori toccati di fila non si disfano a
  /// vicenda.
  void _put(String type, bool enabled) {
    final info = state.value;
    if (info == null) return;
    state = AsyncData(NotificationsInfo(
      vapidPublicKey: info.vapidPublicKey,
      types: [
        for (final pref in info.types)
          if (pref.type == type)
            NotificationTypePref(type: type, enabled: enabled)
          else
            pref,
      ],
    ));
  }
}

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsController, NotificationsInfo>(
        NotificationPrefsController.new);
