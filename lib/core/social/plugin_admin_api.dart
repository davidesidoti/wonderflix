import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'plugin_admin_models.dart';

/// Gli endpoint da admin del plugin WonderFlix Watch Party (spec J §8.3).
/// Gli errori sono [ApiException]: 400 per un annuncio non valido, 403 per
/// chi non è admin.
class PluginAdminApi {
  PluginAdminApi(this._http);

  final JellyfinHttp _http;

  /// L'id del plugin (`Plugin.PluginId`).
  static const pluginId = '882eb47e-668a-4935-ba55-c2858eb4ed90';

  /// Lunghezza massima di un annuncio, come nel plugin.
  static const announcementMaxLength = 500;

  static const _base = '/WonderFlixWatchParty';
  static const _configPath = '/Plugins/$pluginId/Configuration';

  /// Esiti attesi: annuncio non valido, plugin più vecchio (404), Jellyfin
  /// che si riavvia. Nel log come info.
  static const _quiet = {400, 404, ...restartGatewayStatuses};

  /// Manda un annuncio a tutti gli utenti attivi; dà a quanti è arrivato.
  Future<int> announce(String text) async {
    final json = asJsonMap(await _http.post('$_base/Inbox/Announcements',
        body: {'Text': text}, quietStatuses: _quiet));
    final recipients = json['Recipients'];
    if (recipients is! int) throw const ServerErrorException(null);
    return recipients;
  }

  Future<NewTitlesStatus> newTitles() async => parseJson(
      await _http.get('$_base/Inbox/NewTitles', quietStatuses: _quiet),
      NewTitlesStatus.fromJson);

  /// Chiude subito l'ondata dei titoli nuovi ("Invia ora").
  Future<NewTitlesSent> sendNewTitles() async => parseJson(
      await _http.post('$_base/Inbox/NewTitles/Send', quietStatuses: _quiet),
      NewTitlesSent.fromJson);

  /// `null` con un plugin più vecchio della 1.4.0, che non ha l'endpoint.
  Future<SeerrAdminStatus?> seerrStatus() async {
    try {
      // Il tipo esplicito: senza, `T` si deduce come `FutureOr<…>` e il
      // `return` conta come un Future non atteso dentro il `try`.
      return parseJson<SeerrAdminStatus>(
          await _http.get('$_base/Requests/Admin', quietStatuses: _quiet),
          SeerrAdminStatus.fromJson);
    } on NotFoundException {
      return null;
    }
  }

  Future<SeerrTestResult> testSeerr() async => parseJson(
      await _http.post('$_base/Requests/Test', quietStatuses: _quiet),
      SeerrTestResult.fromJson);

  /// Accende o spegne la raccolta delle novità. Rilegge la configurazione
  /// intera del plugin e la riscrive con la sola `NotifyNewTitles` cambiata:
  /// le altre chiavi (Seerr, chiavi nuove) passano intatte. La
  /// configurazione non resta nell'app e non va nel log.
  Future<void> setNotifyNewTitles(bool enabled) async {
    final config = Map<String, dynamic>.of(asJsonMap(await _http.get(_configPath)));
    config['NotifyNewTitles'] = enabled;
    await _http.post(_configPath, body: config);
  }
}
