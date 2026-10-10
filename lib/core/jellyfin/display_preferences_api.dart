import 'jellyfin_http.dart';
import 'json_fields.dart';

/// La Home dell'utente (spec M §6.3): l'ordine delle righe e quelle
/// nascoste, come id (gli sconosciuti li scarta chi li usa).
class HomeUserPrefs {
  const HomeUserPrefs({this.rows = const [], this.hidden = const []});

  /// Nessun ritocco: vale la Home dell'admin.
  static const none = HomeUserPrefs();

  final List<String> rows;
  final List<String> hidden;

  bool get isEmpty => rows.isEmpty && hidden.isEmpty;
}

/// Le `DisplayPreferences` di Jellyfin che tengono la Home dell'utente
/// (spec M §6.3, §8.1): ogni utente le sue, su ogni PC. Gli errori sono
/// `ApiException`.
class DisplayPreferencesApi {
  DisplayPreferencesApi(this._http);

  final JellyfinHttp _http;

  /// Id e client nostri: le preferenze di jellyfin-web non si toccano.
  static const homeId = 'wonderflix-home';
  static const client = 'wonderflix';

  /// Le voci di `CustomPrefs`: id separati da virgole.
  static const rowsKey = 'homeRows';
  static const hiddenKey = 'homeHidden';

  static const _path = '/DisplayPreferences/$homeId';

  /// Jellyfin che si riavvia: nel log come info.
  static const _quiet = restartGatewayStatuses;

  Future<HomeUserPrefs> readHome(String userId) async {
    final custom = jsonMap((await _read(userId))['CustomPrefs']) ?? const {};
    return HomeUserPrefs(
        rows: _ids(custom[rowsKey]), hidden: _ids(custom[hiddenKey]));
  }

  /// Salva ordine e righe nascoste; il resto dell'oggetto e le altre voci di
  /// `CustomPrefs` (anche quelle di jellyfin-web, anche nulle) restano.
  Future<void> writeHome(String userId, HomeUserPrefs prefs) =>
      _update(userId, (custom) {
        custom[rowsKey] = prefs.rows.join(',');
        custom[hiddenKey] = prefs.hidden.join(',');
      });

  /// "Ripristina la Home predefinita": toglie le due voci.
  Future<void> resetHome(String userId) => _update(userId, (custom) {
        custom
          ..remove(rowsKey)
          ..remove(hiddenKey);
      });

  Future<Map<String, dynamic>> _read(String userId) async => asJsonMap(
      await _http.get(_path, query: _query(userId), quietStatuses: _quiet));

  /// Jellyfin riscrive l'oggetto intero: si rilegge, si cambia `CustomPrefs`
  /// e si rimanda tutto.
  Future<void> _update(
      String userId, void Function(Map<String, dynamic> custom) change) async {
    final prefs = Map<String, dynamic>.of(await _read(userId));
    final custom =
        Map<String, dynamic>.of(jsonMap(prefs['CustomPrefs']) ?? const {});
    change(custom);
    prefs['CustomPrefs'] = custom;
    await _http.post(_path,
        query: _query(userId), body: prefs, quietStatuses: _quiet);
  }

  static Map<String, dynamic> _query(String userId) =>
      {'userId': userId, 'client': client};

  static List<String> _ids(Object? raw) => raw is String
      ? [
          for (final id in raw.split(','))
            if (id.trim().isNotEmpty) id.trim(),
        ]
      : const [];
}
