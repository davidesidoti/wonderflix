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
  const SessionUnreachable({this.retryUserId});

  /// Il profilo scelto in "Chi guarda?" che non si è aperto: "Riprova" apre
  /// di nuovo quello. `null`: si riparte da `restore` (che con un solo
  /// profilo lo riapre già).
  final String? retryUserId;
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
    final auth = ref.watch(authServiceProvider);
    http.onUnauthorized = _onUnauthorized;
    // Ogni profilo salvato arriva subito all'interfaccia, anche quello di un
    // accesso che finisce dopo "Annulla".
    auth.onProfilesChanged = _publishProfiles;
    ref.onDispose(() {
      http.onUnauthorized = null;
      auth.onProfilesChanged = null;
    });
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
  /// vale come server irraggiungibile; "Riprova" riapre questo profilo.
  Future<void> openProfile(String userId) async {
    try {
      _apply(_stateFor(await _auth.openProfile(userId), retryUserId: userId));
    } on Object {
      _apply(SessionUnreachable(retryUserId: userId));
    }
  }

  /// Lancia [ApiException] o `ProfileLimitException`: la UI mostra il
  /// messaggio.
  Future<void> loginWithPassword(String username, String password) async {
    _signedIn(await _auth.loginWithPassword(username, password));
  }

  void quickConnectApproved(JellyfinUser user) => _signedIn(user);

  /// Un accesso finito: si apre solo se è il profilo aperto di
  /// `AuthService`. Un accesso superato mentre aspettava il server
  /// ("Annulla", un profilo aperto, un accesso venuto dopo) è salvato ma non
  /// aperto: compare in "Chi guarda?" e la sessione resta com'è.
  void _signedIn(JellyfinUser user) {
    final active = _auth.activeUserId;
    if (active != null && jellyfinIdKey(active) == jellyfinIdKey(user.id)) {
      _apply(SessionSignedIn(user));
    } else {
      _publishProfiles();
    }
  }

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

  /// "Cambia profilo" dalla schermata del server irraggiungibile (spec K
  /// §9.4): di nuovo "Chi guarda?" (o l'accesso, senza profili), con le
  /// credenziali tolte. Serve quando l'errore è di quel profilo (per esempio
  /// un 403 per un account senza accesso da remoto) e "Riprova" non
  /// riuscirebbe mai.
  void backToProfiles() {
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
    // Lo stato cambia subito, senza aspettare le preferenze: la shell non
    // mostra un fotogramma con quelle del PC.
    _apply(_afterLeaving());
    if (removed != null) await _forgetPreferences(removed);
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
    final current = state;
    final elsewhere = current is SessionSignedIn &&
        jellyfinIdKey(current.user.id) != jellyfinIdKey(userId);
    if (leaving) _leaving = true;
    try {
      await _auth.removeProfile(userId);
    } finally {
      if (leaving) _leaving = false;
    }
    if (elsewhere) {
      // Tolto un altro profilo da una sessione: lo stato resta quello che
      // è, anche l'accesso aperto da un 401 nel frattempo.
      _publishProfiles();
    } else {
      // Subito, come per "Esci": senza l'ultimo profilo, nessun "Chi
      // guarda?" vuoto mentre si cancellano le preferenze.
      _apply(_afterLeaving());
    }
    await _forgetPreferences(userId);
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

  SessionState _stateFor(RestoreResult result, {String? retryUserId}) =>
      switch (result) {
        RestoredSession(:final user) => SessionSignedIn(user),
        NoStoredSession() => const SessionSignedOut(),
        StoredSessionExpired(:final userId) =>
          SessionSignedOut(expired: true, reloginUserId: userId),
        RestoreServerUnreachable() =>
          SessionUnreachable(retryUserId: retryUserId),
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
