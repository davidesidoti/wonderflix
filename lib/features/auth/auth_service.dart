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

/// Il 401 di un token scaduto (aprendo un profilo, annullando un token) è un
/// esito atteso: nel log come info, non tra gli errori della diagnostica.
const _expiredTokenStatuses = {401};

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

  /// L'ultimo salvataggio non è riuscito: i profili in memoria sono più
  /// nuovi di quelli dello storage.
  bool _unsaved = false;

  /// Cresce a ogni cambio delle credenziali del client (uscita, accesso
  /// preparato, profilo aperto, accesso riuscito): un accesso partito prima
  /// non le tocca più.
  int _generation = 0;

  /// I profili come li conosce il servizio: letti da `restore`, aggiornati a
  /// ogni modifica.
  ProfileBook get book => _book;

  /// Il profilo aperto; `null` in "Chi guarda?" e nell'accesso.
  String? get activeUserId => _activeUserId;

  /// Chiamato dopo ogni modifica dei profili (anche se lo storage non la
  /// salva): l'interfaccia li rilegge.
  void Function()? onProfilesChanged;

  /// Riparte dai profili (spec K §9.3): nessuno → accesso, uno → si apre,
  /// più di uno → "Chi guarda?".
  Future<RestoreResult> restore() async {
    _deactivate();
    if (_unsaved) {
      // Rileggere lo storage perderebbe i profili che non ha salvato: si
      // tengono quelli in memoria e si riprova a salvarli.
      await _save(_book);
    } else {
      _book = await _store.read();
    }
    return switch (_book.profiles.length) {
      0 => const NoStoredSession(),
      1 => await openProfile(_book.profiles.single.userId),
      _ => const ChooseProfile(),
    };
  }

  /// Apre il profilo [userId] (spec K §9.4): le sue credenziali nel client,
  /// poi `/Users/Me`. Riuscito: nome e immagine aggiornati, ultimo usato.
  /// 401: il profilo è scaduto. Altri errori: server irraggiungibile.
  ///
  /// Chi chiama non sovrappone due aperture: "Chi guarda?" blocca i clic
  /// mentre un profilo si apre, e [restore] parte dietro lo stato occupato
  /// della schermata del server irraggiungibile.
  Future<RestoreResult> openProfile(String userId) async {
    final profile = _book.byId(userId);
    if (profile == null) {
      return _book.isEmpty ? const NoStoredSession() : const ChooseProfile();
    }
    _generation++;
    _http.setCredentials(
        token: profile.accessToken, deviceId: profile.deviceId);
    try {
      final user = await _api.getMe(quietStatuses: _expiredTokenStatuses);
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
    _generation++;
    _activeUserId = null;
    _http.setCredentials(token: null, deviceId: _newDeviceId());
  }

  /// Lancia [ApiException], o [ProfileLimitException] per un sesto profilo.
  /// Il profilo si apre solo se nel frattempo il client non è cambiato (vedi
  /// [activeUserId]).
  Future<JellyfinUser> loginWithPassword(
      String username, String password) async {
    // Il token vale per il DeviceId della richiesta: si legge prima, il
    // client può cambiarlo nel frattempo.
    final deviceId = _http.deviceId;
    final generation = _generation;
    final result = await _api.authenticateByName(username.trim(), password);
    await _adopt(result, deviceId, generation);
    return result.user;
  }

  /// Come [loginWithPassword]. Password e Quick Connect della stessa
  /// schermata partono con la stessa generazione: vale il primo accesso che
  /// finisce, l'altro è superato.
  Future<JellyfinUser> completeQuickConnect(String secret) async {
    final deviceId = _http.deviceId;
    final generation = _generation;
    final result = await _api.authenticateWithQuickConnect(secret);
    await _adopt(result, deviceId, generation);
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
      await _api.logout(quietStatuses: _expiredTokenStatuses);
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

  /// Il client per le chiamate del profilo [userId] (spec K §10.1): quello
  /// principale per il profilo aperto, altrimenti uno con le credenziali del
  /// profilo (che non segnala i 401). `null` se il profilo non c'è.
  JellyfinHttp? clientFor(String userId) {
    final active = _activeUserId;
    if (active != null && jellyfinIdKey(active) == jellyfinIdKey(userId)) {
      return _http;
    }
    final profile = _book.byId(userId);
    return profile == null
        ? null
        : _http.withCredentials(
            token: profile.accessToken, deviceId: profile.deviceId);
  }

  /// Nome e immagine di un profilo salvato, anche non aperto (spec K
  /// §10.4), solo se cambiano.
  Future<void> updateStoredProfile(JellyfinUser user) async {
    final profile = _book.byId(user.id);
    if (profile == null ||
        (profile.name == user.name &&
            profile.imageTag == user.primaryImageTag)) {
      return;
    }
    await _save(_book.upsert(
        profile.copyWith(name: user.name, imageTag: user.primaryImageTag)));
  }

  /// Un profilo non aperto il cui token il server ha rifiutato (401):
  /// "Accedi di nuovo" in "Chi guarda?".
  Future<void> markProfileExpired(String userId) async {
    final profile = _book.byId(userId);
    if (profile == null || profile.expired) return;
    await _save(_book.upsert(profile.copyWith(expired: true)));
  }

  /// Un accesso riuscito (spec K §9.2): il profilo prende il token e il
  /// [deviceId] con cui l'ha ottenuto. Lo stesso utente già salvato non fa un
  /// doppione, e il suo token vecchio si annulla. Con la [generation] di
  /// prima della richiesta superata, il profilo si salva ma non si apre; un
  /// profilo valido dello stesso utente resta com'è.
  Future<void> _adopt(
      AuthResult result, String deviceId, int generation) async {
    final user = result.user;
    final existing = _book.byId(user.id);
    if (existing == null && _book.isFull) {
      await _revoke(result.accessToken, deviceId);
      throw const ProfileLimitException();
    }
    for (final other in _book.profiles) {
      if (other.deviceId == deviceId &&
          jellyfinIdKey(other.userId) != jellyfinIdKey(user.id)) {
        // Non dovrebbe succedere: ogni accesso prepara un DeviceId nuovo.
        _log.warning('DeviceId già del profilo ${other.userId}, '
            'accesso di ${user.id}');
      }
    }
    final profile = StoredProfile(
      userId: user.id,
      name: user.name,
      accessToken: result.accessToken,
      deviceId: deviceId,
      imageTag: user.primaryImageTag,
      lastUsedAt: clock.now(),
    );
    if (generation != _generation) {
      // Mentre si aspettava il server il client è cambiato ("Annulla", un
      // profilo aperto, un altro accesso preparato o già riuscito): le
      // credenziali sono di un altro. Il profilo si salva e compare in "Chi
      // guarda?", ma non si apre e non diventa l'ultimo usato.
      if (existing != null && !existing.expired) {
        // Accesso superato per un utente con un profilo valido (forse
        // aperto, o che si sta aprendo, con il token vecchio): il profilo
        // resta com'è e il token nuovo si annulla, con il suo DeviceId.
        unawaited(_revoke(result.accessToken, deviceId));
        return;
      }
      await _save(_book.upsert(profile));
    } else {
      _http.setCredentials(token: result.accessToken, deviceId: deviceId);
      _activeUserId = user.id;
      // Vince il primo accesso che finisce: un altro della stessa schermata
      // (password e Quick Connect insieme) che finisce dopo è superato, e le
      // credenziali non cambiano sotto una sessione aperta.
      _generation++;
      await _save(_book.upsert(profile).withLast(user.id));
    }
    if (existing != null && existing.accessToken != result.accessToken) {
      // Il token vecchio si annulla con il suo DeviceId (la sessione nuova
      // non c'entra), dopo il salvataggio e senza aspettare: tra il
      // controllo del limite e il salvataggio non c'è nessuna attesa in cui
      // i profili possano cambiare.
      unawaited(_revoke(existing.accessToken, existing.deviceId));
    }
  }

  /// Annulla un token sul server con le sue credenziali; gli errori si
  /// ignorano (il token resta solo lì). Non lancia mai: si può chiamare
  /// senza aspettarla.
  Future<void> _revoke(String token, String deviceId) async {
    try {
      await _apiFor(_http.withCredentials(token: token, deviceId: deviceId))
          .logout(quietStatuses: _expiredTokenStatuses);
    } on Object catch (error) {
      _log.info('token non annullato: ${error.runtimeType}');
    }
  }

  void _deactivate() {
    _generation++;
    _http.setCredentials(token: null, deviceId: null);
    _activeUserId = null;
  }

  Future<void> _save(ProfileBook book) async {
    _book = book;
    try {
      final written = await _store.write(book);
      // Lo storage può aggiungere i profili che aveva (dopo una lettura non
      // riuscita): valgono subito, se intanto i profili non sono cambiati.
      if (identical(_book, book)) _book = written;
      _unsaved = false;
    } on Object catch (error) {
      // Lo storage non salva: i profili valgono lo stesso per questa
      // esecuzione, e la sessione non si rompe; `restore` li tiene.
      _unsaved = true;
      _log.warning('profili non salvati: ${error.runtimeType}');
    }
    onProfilesChanged?.call();
  }
}
