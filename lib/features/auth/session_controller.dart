import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../profiles/profile_preferences.dart';
import 'auth_service.dart';
import 'profiles_state.dart';

final _log = Logger('session');

sealed class SessionState {
  const SessionState();
}

/// Ripristino della sessione in corso (schermata di avvio).
final class SessionStarting extends SessionState {
  const SessionStarting();
}

/// Schermata di accesso (spec K §9.3).
final class SessionSignedOut extends SessionState {
  const SessionSignedOut(
      {this.expired = false, this.reloginUserId, this.adding = false});

  /// `true` se il token del profilo non vale più: l'avviso "Sessione scaduta".
  final bool expired;

  /// Il profilo che rifà l'accesso ("Accedi di nuovo", spec K §9.4): il suo
  /// nome già scritto. Il DeviceId è nuovo, come per ogni accesso.
  final String? reloginUserId;

  /// Si aggiunge un profilo (spec K §9.5).
  final bool adding;
}

final class SessionUnreachable extends SessionState {
  const SessionUnreachable();
}

/// "Chi guarda?" (spec K §9.3): più profili salvati, nessuno aperto.
final class SessionChoosingProfile extends SessionState {
  const SessionChoosingProfile();
}

final class SessionSignedIn extends SessionState {
  const SessionSignedIn(this.user);
  final JellyfinUser user;
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final http = ref.watch(jellyfinHttpProvider);
    http.onUnauthorized = _onUnauthorized;
    ref.onDispose(() => http.onUnauthorized = null);
    return const SessionStarting();
  }

  AuthService get _auth => ref.read(authServiceProvider);

  Future<void> restore() async {
    try {
      _apply(_stateFor(await _auth.restore()));
    } on Object {
      // Difesa in profondità: nessun errore imprevisto deve bloccare l'avvio
      // sulla schermata di splash.
      _apply(const SessionUnreachable());
    }
  }

  /// Apre un profilo da "Chi guarda?" (spec K §9.4). Un errore imprevisto
  /// vale come server irraggiungibile.
  Future<void> openProfile(String userId) async {
    try {
      _apply(_stateFor(await _auth.openProfile(userId)));
    } on Object {
      _apply(const SessionUnreachable());
    }
  }

  /// Lancia [ApiException] o `ProfileLimitException`: la UI mostra il
  /// messaggio.
  Future<void> loginWithPassword(String username, String password) async {
    final user = await _auth.loginWithPassword(username, password);
    if (state is SessionChoosingProfile) {
      // L'accesso è finito dopo "Annulla": il profilo resta salvato e
      // compare in "Chi guarda?", ma non si apre (le sue credenziali escono
      // dal client). Con una sessione aperta nel frattempo (Quick Connect)
      // vale l'ultimo accesso, che ha già le credenziali nel client.
      _auth.deactivate();
      _publishProfiles();
      return;
    }
    _apply(SessionSignedIn(user));
  }

  void quickConnectApproved(JellyfinUser user) => _apply(SessionSignedIn(user));

  /// La schermata di accesso si apre (spec K §9.2): il client prende un
  /// DeviceId nuovo, anche per "Accedi di nuovo". Quick Connect lo usa già
  /// per la richiesta del codice.
  void prepareLogin() => _auth.prepareLogin();

  /// Cambio di profilo (spec K §9.7): le credenziali spariscono, il token
  /// resta salvato, e tutto quello che dipende dall'utente si azzera come
  /// all'uscita. Chi chiama esce prima dal watch party.
  void switchProfile() {
    _auth.deactivate();
    _apply(_afterLeaving());
  }

  /// "Aggiungi profilo" (spec K §9.5): come un cambio, poi l'accesso.
  void addProfile() {
    _auth.deactivate();
    _apply(const SessionSignedOut(adding: true));
  }

  /// "Accedi di nuovo" su un profilo scaduto (spec K §9.4).
  void relogin(String userId) {
    _auth.deactivate();
    _apply(SessionSignedOut(expired: true, reloginUserId: userId));
  }

  /// "Annulla" nell'accesso: di nuovo "Chi guarda?" (spec K §9.3). Il
  /// DeviceId preparato per l'accesso esce dal client.
  void cancelLogin() {
    _auth.deactivate();
    _apply(_afterLeaving());
  }

  /// Un'uscita in corso: il 401 della sua richiesta (token già scaduto) non
  /// apre l'accesso del profilo che si sta togliendo.
  bool _leaving = false;

  /// "Esci" (spec K §9.5): il profilo aperto si toglie dal PC, con le sue
  /// preferenze.
  Future<void> logout() async {
    _leaving = true;
    final String? removed;
    try {
      removed = await _auth.logout();
    } finally {
      _leaving = false;
    }
    if (removed != null) await _forgetPreferences(removed);
    _apply(_afterLeaving());
  }

  /// "Rimuovi" in "Gestisci profili" (spec K §9.4), con le preferenze.
  /// Togliere il profilo aperto è un'uscita; togliere un altro profilo
  /// lascia aperto quello che c'è.
  Future<void> removeProfile(String userId) async {
    final active = _auth.activeUserId;
    // Solo l'uscita ignora i 401: quelli del profilo aperto, mentre se ne
    // toglie un altro, valgono come sempre.
    final leaving =
        active != null && jellyfinIdKey(active) == jellyfinIdKey(userId);
    if (leaving) _leaving = true;
    try {
      await _auth.removeProfile(userId);
    } finally {
      if (leaving) _leaving = false;
    }
    await _forgetPreferences(userId);
    if (_auth.activeUserId != null) {
      // Tolto un altro profilo: si resta in quello aperto.
      _publishProfiles();
    } else {
      _apply(_afterLeaving());
    }
  }

  Future<void> _forgetPreferences(String userId) async {
    try {
      await ProfilePreferences.forget(
          ref.read(sharedPreferencesProvider), userId);
    } on Object catch (error) {
      _log.warning('preferenze del profilo non cancellate: '
          '${error.runtimeType}');
    }
  }

  /// La rilettura dell'utente in corso, se c'è.
  Future<void>? _refreshing;

  /// Rilegge l'utente (spec J §12): per esempio i permessi da admin dopo un
  /// 403. Senza sessione non fa nulla. Chi la chiede mentre una è in corso
  /// riceve la stessa (più schede che prendono un 403 insieme fanno una sola
  /// lettura).
  Future<void> refreshUser() =>
      _refreshing ??= _refreshUser().whenComplete(() => _refreshing = null);

  /// Un errore lascia la sessione com'è (un 401 passa già da
  /// [_onUnauthorized]). Il risultato vale solo se la sessione è ancora
  /// quella dello stesso utente (un'uscita o un altro accesso, nel
  /// frattempo, lo scartano) e solo se qualcosa è cambiato: senza un nuovo
  /// stato il router e la shell non si ricostruiscono. Il profilo prende il
  /// nome e l'immagine nuovi.
  Future<void> _refreshUser() async {
    final before = state;
    if (before is! SessionSignedIn) return;
    try {
      final user = await _auth.currentUser();
      final now = state;
      if (now is! SessionSignedIn || now.user.id != before.user.id) return;
      if (now.user == user) return;
      _apply(SessionSignedIn(user));
      await _updateProfile(user);
    } on ApiException {
      // La sessione resta quella di prima.
    }
  }

  Future<void> _updateProfile(JellyfinUser user) async {
    try {
      await _auth.updateActiveProfile(user);
      _publishProfiles();
    } on Object catch (error) {
      _log.warning('profilo non aggiornato: ${error.runtimeType}');
    }
  }

  /// Un 401 durante la sessione: il profilo è scaduto e rifà l'accesso.
  void _onUnauthorized() {
    final current = state;
    if (current is! SessionSignedIn || _leaving) return;
    unawaited(_auth.markActiveExpired().then((_) => _publishProfiles(),
        onError: (Object error) =>
            _log.warning('profilo non segnato: ${error.runtimeType}')));
    _apply(SessionSignedOut(expired: true, reloginUserId: current.user.id));
  }

  /// Dove si va lasciando un profilo: "Chi guarda?" se ne restano,
  /// altrimenti l'accesso.
  SessionState _afterLeaving() => _auth.book.isEmpty
      ? const SessionSignedOut()
      : const SessionChoosingProfile();

  SessionState _stateFor(RestoreResult result) => switch (result) {
        RestoredSession(:final user) => SessionSignedIn(user),
        NoStoredSession() => const SessionSignedOut(),
        StoredSessionExpired(:final userId) =>
          SessionSignedOut(expired: true, reloginUserId: userId),
        RestoreServerUnreachable() => const SessionUnreachable(),
        ChooseProfile() => const SessionChoosingProfile(),
      };

  void _apply(SessionState next) {
    state = next;
    _publishProfiles();
  }

  void _publishProfiles() {
    if (!ref.mounted) return;
    ref.read(profilesProvider.notifier).set(ProfilesState(
        book: _auth.book, activeUserId: _auth.activeUserId));
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
