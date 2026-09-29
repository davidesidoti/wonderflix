import 'api_exception.dart';
import 'jellyfin_http.dart';

/// Informazioni sul server.
class SystemApi {
  SystemApi(this._http);

  final JellyfinHttp _http;

  /// Versione di Jellyfin (`GET /System/Info/Public`, senza autenticazione).
  Future<String> serverVersion() async {
    final json = asJsonMap(await _http.get('/System/Info/Public'));
    final version = json['Version'];
    if (version is! String) throw const ServerErrorException(null);
    return version;
  }
}
