import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/push/web_push.dart';
import '../../core/social/notifications_api.dart';
import '../auth/profiles_state.dart';
import 'locale_controller.dart';
import 'notification_prefs_controller.dart';

final _log = Logger('push');

final webPushProvider = Provider<WebPush>((ref) => createWebPush());

/// L'endpoint con cui il profilo si è iscritto da questo browser. Più profili
/// possono avere lo stesso (decisione 5 del 31a).
const _endpointPrefix = 'push.endpoint.';
String _endpointKey(String userId) => '$_endpointPrefix${jellyfinIdKey(userId)}';

/// Le notifiche push su questo dispositivo, per il profilo aperto (spec V
/// §4.3). Il riquadro c'è solo con la funzione `push`; all'uscita il
/// `DELETE` parte solo con una chiave salvata, che vuol dire un'iscrizione
/// riuscita (e quindi il plugin con le push).
class DevicePushController extends AsyncNotifier<PushAvailability> {
  @override
  Future<PushAvailability> build() async {
    // Il profilo aperto da `profilesProvider`, non dalla sessione: la
    // sessione chiama [forgetUser] mentre esce.
    final userId = ref.watch(profilesProvider.select((p) => p.activeUserId));
    final availability = await ref.watch(webPushProvider).availability();
    // L'iscrizione del browser può essere solo di un altro profilo.
    if (availability == PushAvailability.active &&
        (userId == null || _prefs.getString(_endpointKey(userId)) == null)) {
      return PushAvailability.ready;
    }
    return availability;
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  String? get _userId => ref.read(profilesProvider).activeUserId;

  /// La lingua dell'app (quella scelta, o quella del sistema risolta come fa
  /// `MaterialApp`, con l'italiano di ripiego): quella delle push.
  String get _language => (ref.read(localeProvider) ??
          basicLocaleListResolution(PlatformDispatcher.instance.locales,
              const [Locale('it'), Locale('en')]))
      .languageCode;

  /// Dal tocco sul pulsante: nessun `await` prima di `subscribe`, che chiede
  /// subito il permesso (su iOS solo dentro il tocco). `false` se non è
  /// riuscito.
  Future<bool> activate() async {
    final vapid = ref.read(notificationPrefsProvider).value?.vapidPublicKey;
    try {
      final keys = await ref.read(webPushProvider).subscribe(vapid ?? '');
      if (keys == null) {
        state = const AsyncData(PushAvailability.denied);
        return true;
      }
      await _register(keys);
      state = const AsyncData(PushAvailability.active);
      return true;
    } on Object catch (error) {
      _log.warning('push non attivate: ${error.runtimeType}');
      return false;
    }
  }

  Future<void> _register(PushKeys keys) async {
    final userId = _userId;
    if (userId == null) throw StateError('nessun profilo aperto');
    await ref.read(notificationsApiProvider).subscribe(
          endpoint: keys.endpoint,
          p256dh: keys.p256dh,
          auth: keys.auth,
          language: _language,
        );
    await _prefs.setString(_endpointKey(userId), keys.endpoint);
  }

  /// "Disattiva": il plugin dimentica il dispositivo per questo profilo.
  /// Con il `DELETE` non riuscito restano attive e risponde `false`.
  Future<bool> deactivate() async {
    final userId = _userId;
    if (userId == null) return false;
    final endpoint = _prefs.getString(_endpointKey(userId));
    try {
      if (endpoint != null) {
        await ref.read(notificationsApiProvider).unsubscribe(endpoint);
      }
    } on Object catch (error) {
      _log.warning('push non disattivate: ${error.runtimeType}');
      return false;
    }
    await _forgetEndpoint(userId);
    state = const AsyncData(PushAvailability.ready);
    return true;
  }

  /// Il profilo esce o si toglie: il `DELETE` con le sue credenziali, prima
  /// che il token sparisca. Un errore non ferma l'uscita: il plugin terrebbe
  /// l'iscrizione di chi esce, quindi il browser si disiscrive e tutte le
  /// chiavi si tolgono (gli altri profili tornano `ready`).
  Future<void> forgetUser(String userId) async {
    final endpoint = _prefs.getString(_endpointKey(userId));
    if (endpoint == null) return;
    try {
      await _apiFor(userId)?.unsubscribe(endpoint);
    } on Object catch (error) {
      _log.warning('iscrizione push non tolta: ${error.runtimeType}');
      for (final key in _prefs.getKeys().toList()) {
        if (key.startsWith(_endpointPrefix)) await _prefs.remove(key);
      }
      await _unsubscribeBrowser();
      return;
    }
    await _forgetEndpoint(userId);
  }

  /// Il profilo aperto usa il client principale; un altro le sue credenziali.
  NotificationsApi? _apiFor(String userId) {
    final current = _userId;
    if (current != null && jellyfinIdKey(current) == jellyfinIdKey(userId)) {
      return ref.read(notificationsApiProvider);
    }
    final client = ref.read(authServiceProvider).clientFor(userId);
    return client == null ? null : NotificationsApi(client);
  }

  /// Toglie la chiave; l'iscrizione del browser solo se nessun profilo la usa
  /// più.
  Future<void> _forgetEndpoint(String userId) async {
    await _prefs.remove(_endpointKey(userId));
    if (_prefs.getKeys().any((k) => k.startsWith(_endpointPrefix))) return;
    await _unsubscribeBrowser();
  }

  Future<void> _unsubscribeBrowser() async {
    try {
      await ref.read(webPushProvider).unsubscribeBrowser();
    } on Object catch (error) {
      _log.warning('browser non disiscritto: ${error.runtimeType}');
    }
  }

  /// La lingua dell'app è cambiata: con le push attive il plugin la riceve,
  /// per i testi delle prossime.
  Future<void> languageChanged() async {
    try {
      if (await future != PushAvailability.active) return;
      final info = await ref.read(notificationPrefsProvider.future);
      final keys = await ref.read(webPushProvider).subscribe(info.vapidPublicKey);
      if (keys != null) await _register(keys);
    } on Object catch (error) {
      _log.warning('lingua delle push non aggiornata: ${error.runtimeType}');
    }
  }
}

final devicePushProvider =
    AsyncNotifierProvider<DevicePushController, PushAvailability>(
        DevicePushController.new);
