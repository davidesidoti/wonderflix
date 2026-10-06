import 'admin_models.dart';
import 'api_exception.dart';
import 'jellyfin_http.dart';

/// Chiamate della pagina Amministrazione a Jellyfin (spec J §8.1). Gli
/// errori sono [ApiException]. Le letture (sessioni, party, informazioni sul
/// server) non chiedono i diritti da admin: solo il riavvio li chiede. Quindi
/// un 403 non dice con certezza che l'utente non è più admin: la pagina
/// rilegge l'utente e decide da lì.
class AdminApi {
  AdminApi(this._http);

  final JellyfinHttp _http;

  /// Come la Dashboard web: le sessioni attive negli ultimi 16 minuti.
  static const activeWithin = Duration(seconds: 960);

  /// Durante un riavvio nginx risponde così finché Jellyfin non torna: sono
  /// esiti attesi, nel log come info (e fuori dagli "Ultimi errori").
  static const _restartStatuses = {502, 503, 504};

  Future<List<SessionEntry>> sessions() async => parseSessions(await _http.get(
      '/Sessions',
      query: {'activeWithinSeconds': activeWithin.inSeconds},
      quietStatuses: _restartStatuses));

  Future<List<PartyGroup>> partyGroups() async => parsePartyGroups(
      await _http.get('/SyncPlay/List', quietStatuses: _restartStatuses));

  Future<ServerInfo> serverInfo() async => parseJson(
      await _http.get('/System/Info', quietStatuses: _restartStatuses),
      ServerInfo.fromJson);

  /// Jellyfin è tornato (`/System/Info/Public`, senza accesso): per l'attesa
  /// del riavvio. Jellyfin 10.11 avvia prima un server di setup, 6-18 s
  /// prima di quello vero, che risponde 200 allo stesso indirizzo ma senza
  /// `StartupWizardCompleted`: conta solo il valore `true`. Qualunque errore,
  /// di rete o del server, o una risposta diversa vale come giù.
  Future<bool> isServerUp() async {
    try {
      final data = await _http.get('/System/Info/Public',
          quietStatuses: _restartStatuses);
      return data is Map<String, dynamic> &&
          data['StartupWizardCompleted'] == true;
    } on ApiException {
      return false;
    }
  }

  Future<void> restart() async {
    await _http.post('/System/Restart');
  }
}
