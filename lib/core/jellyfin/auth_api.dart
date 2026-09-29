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

  Future<JellyfinUser> getMe() async =>
      parseJson(await _http.get('/Users/Me'), JellyfinUser.fromJson);

  Future<void> logout() async {
    await _http.post('/Sessions/Logout');
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
