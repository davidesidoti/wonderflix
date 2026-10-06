import 'admin_models.dart';
import 'api_exception.dart';
import 'jellyfin_http.dart';

/// Chiamate da amministratore a Jellyfin (spec J §8.1). Gli errori sono
/// [ApiException]; un 403 vuol dire che l'utente non è più admin.
class AdminApi {
  AdminApi(this._http);

  final JellyfinHttp _http;

  /// Come la Dashboard web: le sessioni attive negli ultimi 16 minuti.
  static const activeWithin = Duration(seconds: 960);

  /// Durante un riavvio nginx risponde così finché Jellyfin non torna: sono
  /// esiti attesi, nel log come info.
  static const _restartStatuses = {502, 503, 504};

  Future<List<SessionEntry>> sessions() async => parseSessions(await _http
      .get('/Sessions', query: {'activeWithinSeconds': activeWithin.inSeconds}));

  Future<List<PartyGroup>> partyGroups() async =>
      parsePartyGroups(await _http.get('/SyncPlay/List'));

  Future<ServerInfo> serverInfo() async =>
      parseJson(await _http.get('/System/Info'), ServerInfo.fromJson);

  /// Jellyfin risponde (`/System/Info/Public`, senza accesso): per l'attesa
  /// del riavvio. Rete assente o errore del server: giù.
  Future<bool> isServerUp() async {
    try {
      await _http.get('/System/Info/Public', quietStatuses: _restartStatuses);
      return true;
    } on ServerUnreachableException {
      return false;
    } on ServerErrorException {
      return false;
    }
  }

  Future<void> restart() async {
    await _http.post('/System/Restart');
  }
}
