import 'auth_models.dart';
import 'jellyfin_http.dart';

/// Endpoint di autenticazione e Quick Connect (Jellyfin 10.11).
class AuthApi {
  AuthApi(this._http);

  final JellyfinHttp _http;

  Future<AuthResult> authenticateByName(String username, String password) async {
    final data = await _http.post('/Users/AuthenticateByName',
        body: {'Username': username, 'Pw': password});
    return parseJson(data, AuthResult.fromJson);
  }

  /// [quietStatuses]: esiti attesi da chi chiama (per esempio i 502/503/504
  /// di un riavvio di Jellyfin), nel log come info.
  Future<JellyfinUser> getMe({Set<int> quietStatuses = const {}}) async =>
      parseJson(await _http.get('/Users/Me', quietStatuses: quietStatuses),
          JellyfinUser.fromJson);

  /// [quietStatuses] come in [getMe] (per esempio il 401 di un token già
  /// scaduto).
  Future<void> logout({Set<int> quietStatuses = const {}}) async {
    await _http.post('/Sessions/Logout', quietStatuses: quietStatuses);
  }

  Future<bool> quickConnectEnabled() async =>
      await _http.get('/QuickConnect/Enabled') == true;

  Future<QuickConnectState> initiateQuickConnect() async => parseJson(
      await _http.post('/QuickConnect/Initiate'), QuickConnectState.fromJson);

  Future<QuickConnectState> quickConnectState(String secret) async => parseJson(
      await _http.get('/QuickConnect/Connect', query: {'secret': secret}),
      QuickConnectState.fromJson);

  Future<AuthResult> authenticateWithQuickConnect(String secret) async {
    final data = await _http.post('/Users/AuthenticateWithQuickConnect',
        body: {'Secret': secret});
    return parseJson(data, AuthResult.fromJson);
  }
}
