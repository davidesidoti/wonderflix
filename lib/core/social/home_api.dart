import '../jellyfin/json_fields.dart';
import '../jellyfin/jellyfin_http.dart';
import 'home_models.dart';

/// La Home dell'admin e le uscite in arrivo del plugin (spec M §7.2, §7.3).
/// Gli errori sono `ApiException`; un corpo di forma inattesa è
/// `ServerErrorException`.
class HomeApi {
  HomeApi(this._http);

  final JellyfinHttp _http;

  static const _base = '/WonderFlixWatchParty';

  /// Jellyfin che si riavvia: nel log come info.
  static const _quiet = restartGatewayStatuses;

  /// La Home dell'admin: gli id delle righe accese, in ordine; `null` se
  /// mai impostata, anche quando `Rows` manca (Jellyfin non scrive i null).
  Future<List<String>?> layout() async => _rows(
      asJsonMap(await _http.get('$_base/Home/Layout', quietStatuses: _quiet)));

  /// Salva la Home dell'admin (solo admin); `null` torna all'ordine
  /// predefinito. Risponde con quella salvata.
  Future<List<String>?> setLayout(List<String>? rows) async => _rows(asJsonMap(
      await _http.post('$_base/Home/Layout',
          body: {'Rows': rows}, quietStatuses: _quiet)));

  Future<UpcomingPage<UpcomingEpisode>> upcomingSeries() async =>
      UpcomingPage.fromJson(
          asJsonMap(await _http.get('$_base/Upcoming/Series',
              quietStatuses: _quiet)),
          UpcomingEpisode.fromJson);

  Future<UpcomingPage<UpcomingMovie>> upcomingMovies() async =>
      UpcomingPage.fromJson(
          asJsonMap(await _http.get('$_base/Upcoming/Movies',
              quietStatuses: _quiet)),
          UpcomingMovie.fromJson);

  static List<String>? _rows(Map<String, dynamic> json) =>
      json['Rows'] is List ? jsonStrings(json['Rows']) : null;
}
