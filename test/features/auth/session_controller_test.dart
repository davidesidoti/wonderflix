import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/auth_service.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/profile_fakes.dart';
import '../../support/test_data.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;
  late JellyfinHttp http;
  late ProviderContainer container;
  late SharedPreferences prefs;

  /// Il profilo aperto del finto `AuthService`: come il vero, lo tolgono
  /// `deactivate` e `markActiveExpired`.
  String? active;

  final twoProfiles = const ProfileBook()
      .upsert(testProfile(userId: 'u1'))
      .upsert(testProfile(userId: 'u2', name: 'Luigi'));

  SessionController controller() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);
  ProfilesState profiles() => container.read(profilesProvider);

  /// Un accesso riuscito: `AuthService` apre [user], poi il controller.
  void signIn(JellyfinUser user) {
    active = user.id;
    controller().quickConnectApproved(user);
  }

  setUpAll(() => registerFallbackValue(testUser));

  setUp(() async {
    auth = MockAuthService();
    active = null;
    when(() => auth.book).thenReturn(const ProfileBook());
    when(() => auth.activeUserId).thenAnswer((_) => active);
    when(() => auth.deactivate()).thenAnswer((_) => active = null);
    when(() => auth.updateActiveProfile(any())).thenAnswer((_) async {});
    when(() => auth.markActiveExpired()).thenAnswer((_) async {
      active = null;
    });
    http = JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo);
    SharedPreferences.setMockInitialValues({
      'profile.u1.locale': 'en',
      'profile.u2.locale': 'it',
    });
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer.test(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        jellyfinHttpProvider.overrideWithValue(http),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      retry: (_, _) => null,
    );
  });

  test('parte in SessionStarting', () {
    expect(state(), isA<SessionStarting>());
  });

  group('restore', () {
    test('sessione valida → SignedIn, e i profili per l\'interfaccia', () async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoredSession(testUser));
      when(() => auth.book).thenReturn(twoProfiles);
      active = 'u1';

      await controller().restore();

      expect(state(), isA<SessionSignedIn>());
      expect(profiles().book, same(twoProfiles));
      expect(profiles().activeUserId, 'u1');
    });

    test('nessun profilo → SignedOut', () async {
      when(() => auth.restore()).thenAnswer((_) async => const NoStoredSession());
      await controller().restore();
      expect(state(),
          isA<SessionSignedOut>().having((s) => s.expired, 'expired', false));
    });

    test('profilo scaduto → accesso per quel profilo', () async {
      when(() => auth.restore())
          .thenAnswer((_) async => const StoredSessionExpired('u1'));
      await controller().restore();
      expect(
          state(),
          isA<SessionSignedOut>()
              .having((s) => s.expired, 'expired', true)
              .having((s) => s.reloginUserId, 'reloginUserId', 'u1'));
    });

    test('più profili → "Chi guarda?"', () async {
      when(() => auth.restore()).thenAnswer((_) async => const ChooseProfile());
      await controller().restore();
      expect(state(), isA<SessionChoosingProfile>());
    });

    test('server giù → Unreachable', () async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoreServerUnreachable());
      await controller().restore();
      expect(state(), isA<SessionUnreachable>());
    });

    test('errore inatteso → Unreachable', () async {
      when(() => auth.restore()).thenThrow(StateError('boom'));
      await controller().restore();
      expect(state(), isA<SessionUnreachable>());
    });
  });

  group('openProfile', () {
    test('riuscito → SignedIn', () async {
      when(() => auth.openProfile('u2')).thenAnswer((_) async =>
          const RestoredSession(JellyfinUser(id: 'u2', name: 'Luigi')));
      await controller().openProfile('u2');
      expect((state() as SessionSignedIn).user.id, 'u2');
    });

    test('scaduto → accesso per quel profilo', () async {
      when(() => auth.openProfile('u2'))
          .thenAnswer((_) async => const StoredSessionExpired('u2'));
      await controller().openProfile('u2');
      expect((state() as SessionSignedOut).reloginUserId, 'u2');
    });

    test('errore inatteso → Unreachable', () async {
      when(() => auth.openProfile('u2')).thenThrow(StateError('boom'));
      await controller().openProfile('u2');
      expect(state(), isA<SessionUnreachable>());
    });

    test('server giù → Unreachable, con il profilo da riprovare', () async {
      when(() => auth.openProfile('u2'))
          .thenAnswer((_) async => const RestoreServerUnreachable());
      await controller().openProfile('u2');
      expect((state() as SessionUnreachable).retryUserId, 'u2');

      when(() => auth.openProfile('u2')).thenThrow(StateError('boom'));
      await controller().openProfile('u2');
      expect((state() as SessionUnreachable).retryUserId, 'u2');
    });

    test('restore con il server giù: niente profilo da riprovare', () async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoreServerUnreachable());
      await controller().restore();
      expect((state() as SessionUnreachable).retryUserId, isNull);
    });
  });

  test('login riuscito → SignedIn; errore propagato e stato invariato',
      () async {
    when(() => auth.restore()).thenAnswer((_) async => const NoStoredSession());
    await controller().restore();

    when(() => auth.loginWithPassword('mario', 'bad'))
        .thenThrow(const UnauthorizedException());
    await expectLater(controller().loginWithPassword('mario', 'bad'),
        throwsA(isA<UnauthorizedException>()));
    expect(state(), isA<SessionSignedOut>());

    when(() => auth.loginWithPassword('mario', 'ok')).thenAnswer((_) async {
      active = 'u1';
      return testUser;
    });
    await controller().loginWithPassword('mario', 'ok');
    expect(state(), isA<SessionSignedIn>());
  });

  test('quickConnectApproved → SignedIn', () {
    active = 'U-1';
    controller().quickConnectApproved(testUser);
    expect(state(), isA<SessionSignedIn>());
  });

  test('quickConnectApproved di un accesso superato: non si apre', () {
    when(() => auth.book).thenReturn(twoProfiles);
    controller().addProfile();
    controller().cancelLogin();

    // `AuthService` ha salvato il profilo senza aprirlo.
    final withNew =
        twoProfiles.upsert(testProfile(userId: 'u3', name: 'Peach'));
    when(() => auth.book).thenReturn(withNew);
    controller()
        .quickConnectApproved(const JellyfinUser(id: 'u3', name: 'Peach'));

    expect(state(), isA<SessionChoosingProfile>());
    expect(profiles().book, same(withNew));
  });

  group('cambi di profilo', () {
    test('prepareLogin: un DeviceId nuovo, anche per "Accedi di nuovo"', () {
      controller().prepareLogin();
      verify(() => auth.prepareLogin()).called(1);

      controller().relogin('u2');
      controller().prepareLogin();
      verify(() => auth.prepareLogin()).called(1);
    });

    test('switchProfile: credenziali tolte, "Chi guarda?"', () {
      when(() => auth.book).thenReturn(twoProfiles);
      signIn(testUser);

      controller().switchProfile();

      verify(() => auth.deactivate()).called(1);
      expect(state(), isA<SessionChoosingProfile>());
    });

    test('addProfile: accesso per un profilo nuovo', () {
      signIn(testUser);

      controller().addProfile();

      verify(() => auth.deactivate()).called(1);
      expect((state() as SessionSignedOut).adding, isTrue);
    });

    test('relogin: accesso per quel profilo, con l\'avviso', () {
      controller().relogin('u2');
      final signedOut = state() as SessionSignedOut;
      expect(signedOut.reloginUserId, 'u2');
      expect(signedOut.expired, isTrue);
    });

    test('cancelLogin: "Chi guarda?" se ci sono profili, altrimenti accesso',
        () {
      controller().addProfile();
      verify(() => auth.deactivate()).called(1);
      when(() => auth.book).thenReturn(twoProfiles);
      controller().cancelLogin();
      expect(state(), isA<SessionChoosingProfile>());
      // Le credenziali preparate per l'accesso spariscono.
      verify(() => auth.deactivate()).called(1);

      when(() => auth.book).thenReturn(const ProfileBook());
      controller().cancelLogin();
      expect(state(), isA<SessionSignedOut>());
    });

    test('un accesso che finisce dopo "Annulla": salvato, ma non si apre',
        () async {
      when(() => auth.book).thenReturn(twoProfiles);
      controller().addProfile();
      final answer = Completer<JellyfinUser>();
      when(() => auth.loginWithPassword('peach', 'pw'))
          .thenAnswer((_) => answer.future);

      final login = controller().loginWithPassword('peach', 'pw');
      controller().cancelLogin();
      verify(() => auth.deactivate()).called(2);
      // `AuthService` ha salvato il profilo senza aprirlo.
      final withNew =
          twoProfiles.upsert(testProfile(userId: 'u3', name: 'Peach'));
      when(() => auth.book).thenReturn(withNew);
      answer.complete(const JellyfinUser(id: 'u3', name: 'Peach'));
      await login;

      expect(state(), isA<SessionChoosingProfile>());
      // Il profilo compare in "Chi guarda?"; il client non si tocca più.
      expect(profiles().book, same(withNew));
      verifyNever(() => auth.deactivate());
    });

    test('password e Quick Connect insieme: vince il primo (Quick Connect)',
        () async {
      controller().addProfile();
      final answer = Completer<JellyfinUser>();
      when(() => auth.loginWithPassword('mario', 'pw'))
          .thenAnswer((_) => answer.future);

      final login = controller().loginWithPassword('mario', 'pw');
      signIn(const JellyfinUser(id: 'u2', name: 'Luigi'));
      // La password finisce dopo: `AuthService` la salva senza aprirla.
      answer.complete(testUser);
      await login;

      expect((state() as SessionSignedIn).user.id, 'u2');
    });

    test('password e Quick Connect insieme: vince il primo (la password)',
        () async {
      controller().addProfile();
      final answer = Completer<JellyfinUser>();
      when(() => auth.loginWithPassword('mario', 'pw'))
          .thenAnswer((_) => answer.future);

      final login = controller().loginWithPassword('mario', 'pw');
      active = 'u1';
      answer.complete(testUser);
      await login;
      expect((state() as SessionSignedIn).user, same(testUser));

      // Quick Connect finisce dopo: superato, la sessione resta.
      controller()
          .quickConnectApproved(const JellyfinUser(id: 'u2', name: 'Luigi'));
      expect((state() as SessionSignedIn).user, same(testUser));
    });

    test('logout: "Chi guarda?" se restano profili', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      when(() => auth.book)
          .thenReturn(const ProfileBook().upsert(testProfile(userId: 'u2')));
      signIn(testUser);

      await controller().logout();

      verify(() => auth.logout()).called(1);
      expect(state(), isA<SessionChoosingProfile>());
    });

    test('logout dell\'ultimo profilo: accesso', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      signIn(testUser);

      await controller().logout();

      expect(state(), isA<SessionSignedOut>());
    });

    test('removeProfile da "Chi guarda?": resta la scelta finché ci sono profili',
        () async {
      when(() => auth.removeProfile('u2')).thenAnswer((_) async {});
      when(() => auth.book)
          .thenReturn(const ProfileBook().upsert(testProfile(userId: 'u1')));

      await controller().removeProfile('u2');

      verify(() => auth.removeProfile('u2')).called(1);
      expect(state(), isA<SessionChoosingProfile>());
      expect(profiles().book.profiles.single.userId, 'u1');
    });

    test('removeProfile di un altro profilo da una sessione: si resta lì',
        () async {
      signIn(testUser);
      final signedIn = state();
      when(() => auth.removeProfile('u2')).thenAnswer((_) async {});
      final onlyMario =
          const ProfileBook().upsert(testProfile(userId: 'u1'));
      when(() => auth.book).thenReturn(onlyMario);

      await controller().removeProfile('u2');

      expect(state(), same(signedIn));
      verifyNever(() => auth.deactivate());
      expect(profiles().book, same(onlyMario));
      expect(profiles().activeUserId, 'u1');
    });

    test('togliendo un altro profilo, un 401 della sessione apre l\'accesso',
        () async {
      signIn(testUser);
      when(() => auth.book).thenReturn(twoProfiles);
      when(() => auth.removeProfile('u2')).thenAnswer((_) async {
        // Una richiesta del profilo aperto prende un 401 nel frattempo.
        http.onUnauthorized!.call();
      });

      await controller().removeProfile('u2');

      // Resta l'accesso per il profilo scaduto, non "Chi guarda?".
      expect(
          state(),
          isA<SessionSignedOut>()
              .having((s) => s.expired, 'expired', true)
              .having((s) => s.reloginUserId, 'reloginUserId', 'u1'));
      verify(() => auth.markActiveExpired()).called(1);
    });

    test('logout e rimozione cancellano le preferenze del profilo', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      when(() => auth.removeProfile('u2')).thenAnswer((_) async {});
      signIn(testUser);

      await controller().logout();
      expect(prefs.containsKey('profile.u1.locale'), isFalse);
      expect(prefs.getString('profile.u2.locale'), 'it');

      await controller().removeProfile('u2');
      expect(prefs.containsKey('profile.u2.locale'), isFalse);
    });

    test('togliere l\'ultimo profilo: lo stato cambia prima di cancellare le '
        'preferenze', () async {
      when(() => auth.removeProfile('u1')).thenAnswer((_) async {});
      when(() => auth.restore()).thenAnswer((_) async => const ChooseProfile());
      await controller().restore();
      bool? keptWhenLeaving;
      container.listen(sessionControllerProvider, (_, next) {
        keptWhenLeaving = prefs.containsKey('profile.u1.locale');
      });

      await controller().removeProfile('u1');

      // Nessun "Chi guarda?" vuoto mentre si cancellano le preferenze.
      expect(state(), isA<SessionSignedOut>());
      expect(keptWhenLeaving, isTrue);
      expect(prefs.containsKey('profile.u1.locale'), isFalse);
    });

    test('logout: lo stato cambia prima di cancellare le preferenze', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      signIn(testUser);
      bool? keptWhenLeaving;
      container.listen(sessionControllerProvider, (_, next) {
        if (next is! SessionSignedIn) {
          keptWhenLeaving = prefs.containsKey('profile.u1.locale');
        }
      });

      await controller().logout();

      // Senza aspettare le preferenze: la shell non mostra un fotogramma con
      // quelle del PC.
      expect(keptWhenLeaving, isTrue);
      expect(prefs.containsKey('profile.u1.locale'), isFalse);
    });
  });

  test('un 401 durante la sessione: accesso per quel profilo, scaduto',
      () async {
    signIn(testUser);

    http.onUnauthorized!.call();

    expect(
        state(),
        isA<SessionSignedOut>()
            .having((s) => s.expired, 'expired', true)
            .having((s) => s.reloginUserId, 'reloginUserId', 'u1'));
    verify(() => auth.markActiveExpired()).called(1);
  });

  test('un 401 della richiesta di uscita: si esce e basta', () async {
    when(() => auth.logout()).thenAnswer((_) async {
      // Il token era già scaduto: il server risponde 401 al logout.
      http.onUnauthorized!.call();
      return 'u1';
    });
    signIn(testUser);

    await controller().logout();

    verifyNever(() => auth.markActiveExpired());
    expect(state(),
        isA<SessionSignedOut>().having((s) => s.reloginUserId, 'relogin', null));
  });

  group('refreshUser', () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);

    Future<void> restoreAdmin() async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoredSession(admin));
      await controller().restore();
    }

    test('rilegge l\'utente, lo mette nella sessione e nel profilo', () async {
      await restoreAdmin();
      when(() => auth.currentUser()).thenAnswer((_) async => testUser);

      await controller().refreshUser();

      expect((state() as SessionSignedIn).user.isAdministrator, isFalse);
      verify(() => auth.updateActiveProfile(testUser)).called(1);
    });

    test('errore: la sessione resta com\'è', () async {
      await restoreAdmin();
      when(() => auth.currentUser())
          .thenThrow(const ServerUnreachableException());

      await controller().refreshUser();

      expect((state() as SessionSignedIn).user.isAdministrator, isTrue);
    });

    test('senza sessione non chiede nulla', () async {
      await controller().refreshUser();
      verifyNever(() => auth.currentUser());
    });

    test('un utente diverso nel frattempo: il risultato non si applica',
        () async {
      await restoreAdmin();
      final answer = Completer<JellyfinUser>();
      when(() => auth.currentUser()).thenAnswer((_) => answer.future);

      final refreshing = controller().refreshUser();
      const other = JellyfinUser(id: 'u2', name: 'Luigi');
      signIn(other);
      answer.complete(testUser);
      await refreshing;

      expect((state() as SessionSignedIn).user, same(other));
    });

    test('uscito nel frattempo: il risultato non si applica', () async {
      await restoreAdmin();
      final answer = Completer<JellyfinUser>();
      when(() => auth.currentUser()).thenAnswer((_) => answer.future);
      when(() => auth.logout()).thenAnswer((_) async => 'u1');

      final refreshing = controller().refreshUser();
      await controller().logout();
      answer.complete(testUser);
      await refreshing;

      expect(state(), isA<SessionSignedOut>());
    });

    test('utente invariato: nessun nuovo stato', () async {
      await restoreAdmin();
      final before = state();
      // Un'istanza nuova ma uguale: nessun cambio, quindi niente da
      // notificare (il router e la shell non si ricostruiscono).
      when(() => auth.currentUser()).thenAnswer((_) async => JellyfinUser(
          id: admin.id, name: admin.name, isAdministrator: true));

      await controller().refreshUser();

      expect(state(), same(before));
      verifyNever(() => auth.updateActiveProfile(any()));
    });

    test('più richieste insieme: una sola lettura, poi di nuovo', () async {
      await restoreAdmin();
      final answer = Completer<JellyfinUser>();
      when(() => auth.currentUser()).thenAnswer((_) => answer.future);

      final first = controller().refreshUser();
      final second = controller().refreshUser();
      expect(second, same(first));
      answer.complete(testUser);
      await Future.wait([first, second]);

      verify(() => auth.currentUser()).called(1);
      expect((state() as SessionSignedIn).user.isAdministrator, isFalse);

      when(() => auth.currentUser()).thenAnswer((_) async => admin);
      await controller().refreshUser();
      verify(() => auth.currentUser()).called(1);
      expect((state() as SessionSignedIn).user.isAdministrator, isTrue);
    });

    test('un errore non blocca le richieste dopo', () async {
      await restoreAdmin();
      when(() => auth.currentUser())
          .thenThrow(const ServerUnreachableException());
      await controller().refreshUser();

      when(() => auth.currentUser()).thenAnswer((_) async => testUser);
      await controller().refreshUser();

      expect((state() as SessionSignedIn).user.isAdministrator, isFalse);
    });
  });
}
