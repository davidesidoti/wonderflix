import 'dart:async';

import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/user_image_api.dart';
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

  int prepareLoginCalls = 0;
  int switchCalls = 0;
  int addProfileCalls = 0;
  int cancelLoginCalls = 0;
  final openedProfiles = <String>[];
  final reloginProfiles = <String>[];
  final removedProfiles = <String>[];

  @override
  SessionState build() => initial;

  /// Cambia lo stato della sessione, come un login o un logout.
  void set(SessionState next) => state = next;

  @override
  Future<void> restore() async {
    restoreCalls++;
  }

  @override
  Future<void> openProfile(String userId) async => openedProfiles.add(userId);

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
  void prepareLogin() => prepareLoginCalls++;

  @override
  void switchProfile() {
    switchCalls++;
    state = const SessionChoosingProfile();
  }

  @override
  void addProfile() {
    addProfileCalls++;
    state = const SessionSignedOut(adding: true);
  }

  @override
  void relogin(String userId) {
    reloginProfiles.add(userId);
    state = SessionSignedOut(expired: true, reloginUserId: userId);
  }

  @override
  void cancelLogin() {
    cancelLoginCalls++;
    state = const SessionChoosingProfile();
  }

  int backToProfilesCalls = 0;

  @override
  void backToProfiles() {
    backToProfilesCalls++;
    state = const SessionChoosingProfile();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const SessionSignedOut();
  }

  @override
  Future<void> removeProfile(String userId) async =>
      removedProfiles.add(userId);

  @override
  Future<void> refreshUser() async {
    refreshUserCalls++;
    final user = refreshedUser;
    if (user != null) state = SessionSignedIn(user);
  }

  final profileImageCalls = <(String, ImageUpload?)>[];
  Object? profileImageError;
  Completer<void>? profileImageGate;

  /// L'utente che [setProfileImage] dà, come riletto dal server.
  JellyfinUser? profileImageResult;

  @override
  Future<JellyfinUser?> setProfileImage(String userId,
      {ImageUpload? image}) async {
    profileImageCalls.add((userId, image));
    await profileImageGate?.future;
    final error = profileImageError;
    if (error != null) throw error;
    return profileImageResult;
  }
}
