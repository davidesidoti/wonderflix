import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

class FakeSessionController extends SessionController {
  FakeSessionController(this.initial, {this.loginError});

  final SessionState initial;
  final Object? loginError;

  int restoreCalls = 0;
  int logoutCalls = 0;
  final loginAttempts = <(String, String)>[];
  JellyfinUser? approvedUser;
  int refreshUserCalls = 0;

  /// L'utente che [refreshUser] mette nella sessione; `null`: la sessione
  /// resta com'è.
  JellyfinUser? refreshedUser;

  @override
  SessionState build() => initial;

  /// Cambia lo stato della sessione, come un login o un logout.
  void set(SessionState next) => state = next;

  @override
  Future<void> restore() async {
    restoreCalls++;
  }

  @override
  Future<void> loginWithPassword(String username, String password) async {
    loginAttempts.add((username, password));
    final error = loginError;
    if (error != null) throw error;
    state = SessionSignedIn(JellyfinUser(id: 'u1', name: username));
  }

  @override
  void quickConnectApproved(JellyfinUser user) {
    approvedUser = user;
    state = SessionSignedIn(user);
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const SessionSignedOut();
  }

  @override
  Future<void> refreshUser() async {
    refreshUserCalls++;
    final user = refreshedUser;
    if (user != null) state = SessionSignedIn(user);
  }
}
