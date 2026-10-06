import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_api.dart';
import '../../core/jellyfin/auth_models.dart';
import '../../core/jellyfin/jellyfin_http.dart';
import '../../core/storage/session_store.dart';

sealed class RestoreResult {
  const RestoreResult();
}

final class RestoredSession extends RestoreResult {
  const RestoredSession(this.user);
  final JellyfinUser user;
}

final class NoStoredSession extends RestoreResult {
  const NoStoredSession();
}

final class StoredSessionExpired extends RestoreResult {
  const StoredSessionExpired();
}

final class RestoreServerUnreachable extends RestoreResult {
  const RestoreServerUnreachable();
}

/// Login, ripristino e logout. Nessuna dipendenza da Flutter.
class AuthService {
  AuthService({
    required JellyfinHttp http,
    required AuthApi api,
    required SessionStore store,
  })  : _http = http,
        _api = api,
        _store = store;

  final JellyfinHttp _http;
  final AuthApi _api;
  final SessionStore _store;

  Future<RestoreResult> restore() async {
    final session = await _store.read();
    if (session == null) return const NoStoredSession();

    _http.token = session.accessToken;
    try {
      return RestoredSession(await _api.getMe());
    } on UnauthorizedException {
      await clearLocalSession();
      return const StoredSessionExpired();
    } on ApiException {
      return const RestoreServerUnreachable();
    }
  }

  /// L'utente della sessione riletto dal server (`/Users/Me`), per esempio
  /// dopo un 403 di una chiamata da admin (spec J §12). Lancia
  /// [ApiException].
  Future<JellyfinUser> currentUser() => _api.getMe();

  Future<JellyfinUser> loginWithPassword(String username, String password) async {
    final result = await _api.authenticateByName(username.trim(), password);
    await _adopt(result);
    return result.user;
  }

  Future<JellyfinUser> completeQuickConnect(String secret) async {
    final result = await _api.authenticateWithQuickConnect(secret);
    await _adopt(result);
    return result.user;
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } on ApiException {
      // Il token viene comunque dimenticato in locale.
    } finally {
      await clearLocalSession();
    }
  }

  Future<void> clearLocalSession() async {
    _http.token = null;
    await _store.clear();
  }

  Future<void> _adopt(AuthResult result) async {
    _http.token = result.accessToken;
    await _store.write(
        StoredSession(userId: result.user.id, accessToken: result.accessToken));
  }
}
