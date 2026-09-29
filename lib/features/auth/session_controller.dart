import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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

  void _onUnauthorized() {
    if (state is! SessionSignedIn) return;
    unawaited(_auth.clearLocalSession());
    state = const SessionSignedOut(expired: true);
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
