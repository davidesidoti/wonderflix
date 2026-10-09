import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'account_models.dart';
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

  /// La configurazione del plugin è un endpoint di Jellyfin, non del plugin:
  /// un 400 o un 404 lì sono errori veri. Solo il riavvio è atteso.
  static const _configQuiet = restartGatewayStatuses;

  static const _account = '$_base/Account/Admin';

  /// Esiti attesi delle azioni sugli utenti (spec L §7.6): utente
  /// sconosciuto (400), admin o disattivato (403 `NotAllowed`), senza
  /// contatti (409), invio non riuscito (502, già fra gli stati di
  /// [restartGatewayStatuses]: un duplicato nel set costante non vale).
  /// Nel log come info.
  static const _accountQuiet = {400, 403, 404, 409, ...restartGatewayStatuses};

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
  /// configurazione non resta nell'app e non va nel log. Se quello che
  /// torna non sembra la configurazione vera, non si scrive niente.
  Future<void> setNotifyNewTitles(bool enabled) async {
    final config = Map<String, dynamic>.of(asJsonMap(
        await _http.get(_configPath, quietStatuses: _configQuiet)));
    // Una POST di una mappa parziale riporterebbe ai valori di default le
    // chiavi che mancano (URL, chiave e segreto di Seerr): meglio un errore.
    if (config['NotifyNewTitles'] is! bool ||
        !config.containsKey('SeerrApiKey')) {
      throw const ServerErrorException(null);
    }
    config['NotifyNewTitles'] = enabled;
    await _http.post(_configPath, body: config, quietStatuses: _configQuiet);
  }

  /// Gli utenti con i loro contatti per il recupero, in ordine di nome.
  Future<List<AdminAccountUser>> accountUsers() async {
    final json = await _http.get('$_account/Users', quietStatuses: _quiet);
    if (json is! List) throw const ServerErrorException(null);
    return [for (final raw in json) parseJson(raw, AdminAccountUser.fromJson)];
  }

  /// Manda all'utente un codice di recupero: i canali dove è arrivato. Gli
  /// errori hanno il `{Code}` del plugin ([pluginErrorCode]).
  Future<List<AccountChannel>> sendRecoveryCode(String userId,
      {required String language}) async {
    final json = asJsonMap(await _http.post('$_account/Users/$userId/Recovery',
        body: {'Language': language}, quietStatuses: _accountQuiet));
    final channels = json['Channels'];
    if (channels is! List) throw const ServerErrorException(null);
    return [for (final raw in channels) ?AccountChannel.fromWire(raw)];
  }

  /// Toglie Discord ed email dell'utente; il plugin annulla anche i codici
  /// già mandati.
  Future<void> unlinkContacts(String userId) async {
    await _http.delete('$_account/Users/$userId/Contacts',
        quietStatuses: _accountQuiet);
  }

  Future<AccountAdminStatus> accountStatus() async => parseJson(
      await _http.get('$_account/Status', quietStatuses: _quiet),
      AccountAdminStatus.fromJson);

  /// Un messaggio di prova per canale, ai contatti dell'admin: senza i campi
  /// `Discord` ed `Email`, che usa la Dashboard.
  Future<AccountTestResult> testAccountChannels(
          {required String language}) async =>
      parseJson(
          await _http.post('$_account/Test',
              body: {'Language': language}, quietStatuses: _quiet),
          AccountTestResult.fromJson);
}

/// Il `{Code}` di un errore del plugin (spec L §7.6), se c'è: nel corpo di
/// un 403 o di un altro errore del server.
String? pluginErrorCode(Object error) {
  final body = switch (error) {
    ForbiddenException(:final body) => body,
    ServerErrorException(:final body) => body,
    _ => null,
  };
  if (body is! Map) return null;
  final code = body['Code'];
  return code is String ? code : null;
}
