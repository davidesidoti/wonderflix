import '../jellyfin/jellyfin_http.dart';
import '../jellyfin/api_exception.dart';
import 'notifications_models.dart';

/// Gli endpoint delle notifiche push del plugin (spec V §4.1, dal plugin
/// 1.17.0). Gli errori sono [ApiException]: 400 per un tipo sconosciuto o
/// una sottoscrizione non valida.
class NotificationsApi {
  NotificationsApi(this._http);

  final JellyfinHttp _http;

  static const _base = '/WonderFlixWatchParty/Notifications';

  /// Esiti attesi: richiesta non valida, plugin più vecchio (404), Jellyfin
  /// che si riavvia. Nel log come info.
  static const _quiet = {400, 404, ...restartGatewayStatuses};

  Future<NotificationsInfo> get() async => parseJson(
      await _http.get(_base, quietStatuses: _quiet), NotificationsInfo.fromJson);

  Future<void> setEnabled(String type, bool enabled) async {
    await _http.put('$_base/Types/$type',
        body: {'Enabled': enabled}, quietStatuses: _quiet);
  }

  /// Registra il dispositivo (le chiavi del `PushSubscription` del browser).
  Future<void> subscribe({
    required String endpoint,
    required String p256dh,
    required String auth,
    required String language,
  }) async {
    await _http.post('$_base/Subscriptions',
        body: {
          'Endpoint': endpoint,
          'P256dh': p256dh,
          'Auth': auth,
          'Language': language,
        },
        quietStatuses: _quiet);
  }

  Future<void> unsubscribe(String endpoint) async {
    await _http.delete('$_base/Subscriptions',
        body: {'Endpoint': endpoint}, quietStatuses: _quiet);
  }
}
