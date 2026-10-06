import 'activity_models.dart';
import 'admin_models.dart';
import 'api_exception.dart';
import 'jellyfin_http.dart';
import 'maintenance_models.dart';

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

  Future<List<SessionEntry>> sessions() async => parseSessions(await _http.get(
      '/Sessions',
      query: {'activeWithinSeconds': activeWithin.inSeconds},
      quietStatuses: restartGatewayStatuses));

  Future<List<PartyGroup>> partyGroups() async => parsePartyGroups(
      await _http.get('/SyncPlay/List', quietStatuses: restartGatewayStatuses));

  Future<ServerInfo> serverInfo() async => parseJson(
      await _http.get('/System/Info', quietStatuses: restartGatewayStatuses),
      ServerInfo.fromJson);

  /// Jellyfin è tornato (`/System/Info/Public`, senza accesso): per l'attesa
  /// del riavvio. Jellyfin 10.11 avvia prima un server di setup, 6-18 s
  /// prima di quello vero, che può rispondere 200 allo stesso indirizzo senza
  /// `StartupWizardCompleted` a `true`: conta solo quel valore. Qualunque errore,
  /// di rete o del server, o una risposta diversa vale come giù.
  Future<bool> isServerUp() async {
    try {
      final data = await _http.get('/System/Info/Public',
          quietStatuses: restartGatewayStatuses);
      return data is Map<String, dynamic> &&
          data['StartupWizardCompleted'] == true;
    } on ApiException {
      return false;
    }
  }

  /// Jellyfin può fermarsi prima di rispondere: nginx dà 502/503/504, che il
  /// chiamante conta come riavvio partito (nel log, info).
  Future<void> restart() async {
    await _http.post('/System/Restart', quietStatuses: restartGatewayStatuses);
  }

  /// Voci del registro per pagina (spec J §9.5).
  static const activityPageSize = 50;

  /// I parametri di "Scansiona libreria" della Dashboard web 10.11.9
  /// (`refreshdialog.js`, modo "scan"), copiati uguali per avere lo stesso
  /// comportamento: metadati e immagini solo dove mancano. `Recursive` non è
  /// nell'OpenAPI di 10.11.9 e il server lo ignora: l'aggiornamento di una
  /// libreria è comunque ricorsivo.
  static const _scanLibraryQuery = <String, Object>{
    'Recursive': true,
    'ImageRefreshMode': 'Default',
    'MetadataRefreshMode': 'Default',
    'ReplaceAllImages': false,
    'RegenerateTrickplay': false,
    'ReplaceAllMetadata': false,
  };

  Future<List<LibraryFolder>> libraries() async => parseLibraries(await _http
      .get('/Library/VirtualFolders', quietStatuses: restartGatewayStatuses));

  /// Scansiona tutte le librerie (l'attività "Scansione della libreria").
  Future<void> scanAll() async {
    await _http.post('/Library/Refresh');
  }

  Future<void> scanLibrary(String itemId) async {
    await _http.post('/Items/$itemId/Refresh', query: _scanLibraryQuery);
  }

  /// Le attività pianificate visibili nella Dashboard.
  Future<List<ScheduledTask>> tasks() async => parseTasks(await _http.get(
      '/ScheduledTasks',
      query: {'isHidden': false},
      quietStatuses: restartGatewayStatuses));

  Future<void> startTask(String id) async {
    await _http.post('/ScheduledTasks/Running/$id');
  }

  Future<void> stopTask(String id) async {
    await _http.delete('/ScheduledTasks/Running/$id');
  }

  /// Una pagina del registro dalla voce [startIndex], dalla più recente.
  /// [hasUserId]: `true` solo le voci degli utenti, `false` solo quelle di
  /// sistema, `null` tutte.
  Future<ActivityPage> activity({required int startIndex, bool? hasUserId}) async =>
      parseActivityPage(await _http.get('/System/ActivityLog/Entries',
          query: {
            'startIndex': startIndex,
            'limit': activityPageSize,
            'hasUserId': ?hasUserId,
          },
          quietStatuses: restartGatewayStatuses));
}
