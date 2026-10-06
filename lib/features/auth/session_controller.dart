import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_models.dart';
import 'auth_service.dart';

sealed class SessionState {
  const SessionState();
}

/// Ripristino della sessione in corso (schermata di avvio).
final class SessionStarting extends SessionState {
  const SessionStarting();
}

final class SessionSignedOut extends SessionState {
  const SessionSignedOut({this.expired = false});

  /// `true` se l'utente è stato disconnesso per un token non più valido.
  final bool expired;
}

final class SessionUnreachable extends SessionState {
  const SessionUnreachable();
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
      final result = await _auth.restore();
      state = switch (result) {
        RestoredSession(:final user) => SessionSignedIn(user),
        NoStoredSession() => const SessionSignedOut(),
        StoredSessionExpired() => const SessionSignedOut(expired: true),
        RestoreServerUnreachable() => const SessionUnreachable(),
      };
    } on Object {
      // Difesa in profondità: nessun errore imprevisto deve bloccare l'avvio
      // sulla schermata di splash.
      state = const SessionUnreachable();
    }
  }

  /// Lancia [ApiException] in caso di errore: la UI mostra il messaggio.
  Future<void> loginWithPassword(String username, String password) async {
    final user = await _auth.loginWithPassword(username, password);
    state = SessionSignedIn(user);
  }

  void quickConnectApproved(JellyfinUser user) => state = SessionSignedIn(user);

  Future<void> logout() async {
    await _auth.logout();
    state = const SessionSignedOut();
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
  /// stato il router e la shell non si ricostruiscono.
  Future<void> _refreshUser() async {
    final before = state;
    if (before is! SessionSignedIn) return;
    try {
      final user = await _auth.currentUser();
      final now = state;
      if (now is! SessionSignedIn || now.user.id != before.user.id) return;
      if (now.user == user) return;
      state = SessionSignedIn(user);
    } on ApiException {
      // La sessione resta quella di prima.
    }
  }

  void _onUnauthorized() {
    if (state is! SessionSignedIn) return;
    unawaited(_auth.clearLocalSession());
    state = const SessionSignedOut(expired: true);
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
