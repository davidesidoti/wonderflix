import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_api.dart';
import '../../core/jellyfin/auth_models.dart';
import '../../core/jellyfin/jellyfin_http.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/storage/profile_store.dart';

final _log = Logger('auth');

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

/// Il server ha rifiutato il token del profilo [userId] (401).
final class StoredSessionExpired extends RestoreResult {
  const StoredSessionExpired(this.userId);
  final String userId;
}

final class RestoreServerUnreachable extends RestoreResult {
  const RestoreServerUnreachable();
}

/// Più profili salvati: si sceglie in "Chi guarda?" (spec K §9.3).
final class ChooseProfile extends RestoreResult {
  const ChooseProfile();
}

/// Profili, accesso e uscita (spec K §9). Nessuna dipendenza da Flutter.
class AuthService {
  AuthService({
    required JellyfinHttp http,
    required AuthApi api,
    required ProfileStore store,
    AuthApi Function(JellyfinHttp http)? apiFor,
    String Function()? newDeviceId,
  })  : _http = http,
        _api = api,
        _store = store,
        _apiFor = apiFor ?? AuthApi.new,
        _newDeviceId = newDeviceId ?? (() => const Uuid().v4());

  final JellyfinHttp _http;
  final AuthApi _api;
  final ProfileStore _store;

  /// Le chiamate con le credenziali di un profilo non attivo.
  final AuthApi Function(JellyfinHttp http) _apiFor;
  final String Function() _newDeviceId;

  ProfileBook _book = const ProfileBook();
  String? _activeUserId;

  /// I profili come li conosce il servizio: letti da `restore`, aggiornati a
  /// ogni modifica.
  ProfileBook get book => _book;

  /// Il profilo aperto; `null` in "Chi guarda?" e nell'accesso.
  String? get activeUserId => _activeUserId;

  Future<RestoreResult> restore() async {
    _deactivate();
    _book = await _store.read();
    return switch (_book.profiles.length) {
      0 => const NoStoredSession(),
      1 => await openProfile(_book.profiles.single.userId),
      _ => const ChooseProfile(),
    };
  }

  /// Apre il profilo [userId] (spec K §9.4): le sue credenziali nel client,
  /// poi `/Users/Me`. Riuscito: nome e immagine aggiornati, ultimo usato.
  /// 401: il profilo è scaduto. Altri errori: server irraggiungibile.
  Future<RestoreResult> openProfile(String userId) async {
    final profile = _book.byId(userId);
    if (profile == null) {
      return _book.isEmpty ? const NoStoredSession() : const ChooseProfile();
    }
    _http.setCredentials(
        token: profile.accessToken, deviceId: profile.deviceId);
    try {
      final user = await _api.getMe();
      _activeUserId = profile.userId;
      await _save(_book
          .upsert(profile.copyWith(
            name: user.name,
            imageTag: user.primaryImageTag,
            lastUsedAt: clock.now(),
            expired: false,
          ))
          .withLast(profile.userId));
      return RestoredSession(user);
    } on UnauthorizedException {
      _deactivate();
      await _save(_book.upsert(profile.copyWith(expired: true)));
      return StoredSessionExpired(profile.userId);
    } on ApiException {
      _deactivate();
      return const RestoreServerUnreachable();
    }
  }

  /// L'utente della sessione riletto dal server (`/Users/Me`), per esempio
  /// dopo un 403 di una chiamata da admin (spec J §12). Lancia
  /// [ApiException]. Durante un riavvio di Jellyfin la pagina Amministrazione
  /// la chiama ancora: i 502/503/504 vanno nel log come info.
  Future<JellyfinUser> currentUser() =>
      _api.getMe(quietStatuses: restartGatewayStatuses);

  /// Prepara un accesso (spec K §9.2): nessun token e un DeviceId nuovo.
  /// Ogni accesso ha un DeviceId nuovo, anche "Accedi di nuovo": due profili
  /// non lo condividono mai (il nome si può cambiare, e Quick Connect può
  /// approvarlo un altro utente), e annullare il token vecchio non chiude la
  /// sessione nuova.
  void prepareLogin() {
    _activeUserId = null;
    _http.setCredentials(token: null, deviceId: _newDeviceId());
  }

  /// Lancia [ApiException], o [ProfileLimitException] per un sesto profilo.
  Future<JellyfinUser> loginWithPassword(
      String username, String password) async {
    // Il token vale per il DeviceId della richiesta: si legge prima, il
    // client può cambiarlo nel frattempo.
    final deviceId = _http.deviceId;
    final result = await _api.authenticateByName(username.trim(), password);
    await _adopt(result, deviceId);
    return result.user;
  }

  Future<JellyfinUser> completeQuickConnect(String secret) async {
    // Come per la password: il DeviceId della richiesta.
    final deviceId = _http.deviceId;
    final result = await _api.authenticateWithQuickConnect(secret);
    await _adopt(result, deviceId);
    return result.user;
  }

  /// Esce dal profilo aperto (spec K §9.5): annulla il token e toglie il
  /// profilo dal PC. Dà l'id del profilo tolto (`null` senza profilo aperto).
  Future<String?> logout() async {
    final userId = _activeUserId;
    if (userId == null) {
      _deactivate();
      return null;
    }
    try {
      await _api.logout();
    } on ApiException catch (error) {
      // Il token resta solo sul server: qui si dimentica comunque.
      _log.info('token non annullato: ${error.runtimeType}');
    }
    _deactivate();
    await _save(_book.remove(userId));
    return userId;
  }

  /// Toglie il profilo [userId] dal PC (spec K §9.4), con il suo token
  /// annullato sul server (con le sue credenziali; gli errori si ignorano).
  Future<void> removeProfile(String userId) async {
    final active = _activeUserId;
    if (active != null && jellyfinIdKey(active) == jellyfinIdKey(userId)) {
      await logout();
      return;
    }
    final profile = _book.byId(userId);
    if (profile == null) return;
    await _save(_book.remove(userId));
    // Il token si annulla senza aspettare: gli errori si ignorano comunque,
    // e con il server giù si aspetterebbe il timeout della connessione.
    unawaited(_revoke(profile.accessToken, profile.deviceId));
  }

  /// Cambio di profilo (spec K §9.7): le credenziali spariscono dal client;
  /// il token resta valido e salvato.
  void deactivate() => _deactivate();

  /// Un 401 durante la sessione: il profilo aperto è scaduto.
  Future<void> markActiveExpired() async {
    final userId = _activeUserId;
    _deactivate();
    final profile = userId == null ? null : _book.byId(userId);
    if (profile != null) {
      await _save(_book.upsert(profile.copyWith(expired: true)));
    }
  }

  /// L'utente riletto (spec J §12): nome e immagine nel profilo aperto, solo
  /// se cambiano.
  Future<void> updateActiveProfile(JellyfinUser user) async {
    final active = _activeUserId;
    final profile = active == null ? null : _book.byId(active);
    if (profile == null ||
        jellyfinIdKey(profile.userId) != jellyfinIdKey(user.id)) {
      return;
    }
    if (profile.name == user.name && profile.imageTag == user.primaryImageTag) {
      return;
    }
    await _save(_book.upsert(
        profile.copyWith(name: user.name, imageTag: user.primaryImageTag)));
  }

  /// Un accesso riuscito (spec K §9.2): il profilo prende il token e il
  /// [deviceId] con cui l'ha ottenuto. Lo stesso utente già salvato non fa un
  /// doppione, e il suo token vecchio si annulla.
  Future<void> _adopt(AuthResult result, String deviceId) async {
    final user = result.user;
    final existing = _book.byId(user.id);
    if (existing == null && _book.isFull) {
      await _revoke(result.accessToken, deviceId);
      throw const ProfileLimitException();
    }
    if (existing != null && existing.accessToken != result.accessToken) {
      await _revoke(existing.accessToken, existing.deviceId);
    }
    _http.setCredentials(token: result.accessToken, deviceId: deviceId);
    _activeUserId = user.id;
    await _save(_book
        .upsert(StoredProfile(
          userId: user.id,
          name: user.name,
          accessToken: result.accessToken,
          deviceId: deviceId,
          imageTag: user.primaryImageTag,
          lastUsedAt: clock.now(),
        ))
        .withLast(user.id));
  }

  /// Annulla un token sul server con le sue credenziali; gli errori si
  /// ignorano (il token resta solo lì). Non lancia mai: si può chiamare
  /// senza aspettarla.
  Future<void> _revoke(String token, String deviceId) async {
    try {
      await _apiFor(_http.withCredentials(token: token, deviceId: deviceId))
          .logout();
    } on Object catch (error) {
      _log.info('token non annullato: ${error.runtimeType}');
    }
  }

  void _deactivate() {
    _http.setCredentials(token: null, deviceId: null);
    _activeUserId = null;
  }

  Future<void> _save(ProfileBook book) async {
    _book = book;
    try {
      await _store.write(book);
    } on Object catch (error) {
      // Lo storage non salva: i profili valgono lo stesso per questa
      // esecuzione, e la sessione non si rompe. Al prossimo avvio si legge
      // l'ultimo elenco salvato.
      _log.warning('profili non salvati: ${error.runtimeType}');
    }
  }
}
