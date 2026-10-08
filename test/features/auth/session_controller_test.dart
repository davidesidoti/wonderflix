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

  final twoProfiles = const ProfileBook()
      .upsert(testProfile(userId: 'u1'))
      .upsert(testProfile(userId: 'u2', name: 'Luigi'));

  SessionController controller() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);
  ProfilesState profiles() => container.read(profilesProvider);

  setUpAll(() => registerFallbackValue(testUser));

  setUp(() async {
    auth = MockAuthService();
    when(() => auth.book).thenReturn(const ProfileBook());
    when(() => auth.activeUserId).thenReturn(null);
    when(() => auth.updateActiveProfile(any())).thenAnswer((_) async {});
    when(() => auth.markActiveExpired()).thenAnswer((_) async {});
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
      when(() => auth.activeUserId).thenReturn('u1');

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

    when(() => auth.loginWithPassword('mario', 'ok'))
        .thenAnswer((_) async => testUser);
    await controller().loginWithPassword('mario', 'ok');
    expect(state(), isA<SessionSignedIn>());
  });

  test('quickConnectApproved → SignedIn', () {
    controller().quickConnectApproved(testUser);
    expect(state(), isA<SessionSignedIn>());
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
      controller().quickConnectApproved(testUser);

      controller().switchProfile();

      verify(() => auth.deactivate()).called(1);
      expect(state(), isA<SessionChoosingProfile>());
    });

    test('addProfile: accesso per un profilo nuovo', () {
      controller().quickConnectApproved(testUser);

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
      final withNew =
          twoProfiles.upsert(testProfile(userId: 'u3', name: 'Peach'));
      when(() => auth.book).thenReturn(withNew);
      answer.complete(const JellyfinUser(id: 'u3', name: 'Peach'));
      await login;

      expect(state(), isA<SessionChoosingProfile>());
      // Le credenziali del profilo nuovo spariscono dal client; il profilo
      // compare in "Chi guarda?".
      verify(() => auth.deactivate()).called(1);
      expect(profiles().book, same(withNew));
    });

    test('password e Quick Connect insieme: vale l\'ultimo accesso', () async {
      controller().addProfile();
      verify(() => auth.deactivate()).called(1);
      final answer = Completer<JellyfinUser>();
      when(() => auth.loginWithPassword('mario', 'pw'))
          .thenAnswer((_) => answer.future);

      final login = controller().loginWithPassword('mario', 'pw');
      controller()
          .quickConnectApproved(const JellyfinUser(id: 'u2', name: 'Luigi'));
      answer.complete(testUser);
      await login;

      // Le credenziali nel client sono quelle della password, arrivata dopo.
      expect((state() as SessionSignedIn).user, same(testUser));
      verifyNever(() => auth.deactivate());
    });

    test('logout: "Chi guarda?" se restano profili', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      when(() => auth.book)
          .thenReturn(const ProfileBook().upsert(testProfile(userId: 'u2')));
      controller().quickConnectApproved(testUser);

      await controller().logout();

      verify(() => auth.logout()).called(1);
      expect(state(), isA<SessionChoosingProfile>());
    });

    test('logout dell\'ultimo profilo: accesso', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      controller().quickConnectApproved(testUser);

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
      when(() => auth.activeUserId).thenReturn('u1');
      controller().quickConnectApproved(testUser);
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
      when(() => auth.activeUserId).thenReturn('u1');
      controller().quickConnectApproved(testUser);
      SessionState? during;
      when(() => auth.removeProfile('u2')).thenAnswer((_) async {
        // Una richiesta del profilo aperto prende un 401 nel frattempo.
        http.onUnauthorized!.call();
        during = state();
      });

      await controller().removeProfile('u2');

      expect(during, isA<SessionSignedOut>()
          .having((s) => s.reloginUserId, 'reloginUserId', 'u1'));
      verify(() => auth.markActiveExpired()).called(1);
    });

    test('logout e rimozione cancellano le preferenze del profilo', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      when(() => auth.removeProfile('u2')).thenAnswer((_) async {});
      controller().quickConnectApproved(testUser);

      await controller().logout();
      expect(prefs.containsKey('profile.u1.locale'), isFalse);
      expect(prefs.getString('profile.u2.locale'), 'it');

      await controller().removeProfile('u2');
      expect(prefs.containsKey('profile.u2.locale'), isFalse);
    });
  });

  test('un 401 durante la sessione: accesso per quel profilo, scaduto',
      () async {
    controller().quickConnectApproved(testUser);

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
    controller().quickConnectApproved(testUser);

    await controller().logout();

    verifyNever(() => auth.markActiveExpired());
    expect(state(),
        isA<SessionSignedOut>().having((s) => s.reloginUserId, 'relogin', null));
  });

  group('refreshUser', () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);

    Future<void> signIn() async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoredSession(admin));
      await controller().restore();
    }

    test('rilegge l\'utente, lo mette nella sessione e nel profilo', () async {
      await signIn();
      when(() => auth.currentUser()).thenAnswer((_) async => testUser);

      await controller().refreshUser();

      expect((state() as SessionSignedIn).user.isAdministrator, isFalse);
      verify(() => auth.updateActiveProfile(testUser)).called(1);
    });

    test('errore: la sessione resta com\'è', () async {
      await signIn();
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
      await signIn();
      final answer = Completer<JellyfinUser>();
      when(() => auth.currentUser()).thenAnswer((_) => answer.future);

      final refreshing = controller().refreshUser();
      const other = JellyfinUser(id: 'u2', name: 'Luigi');
      controller().quickConnectApproved(other);
      answer.complete(testUser);
      await refreshing;

      expect((state() as SessionSignedIn).user, same(other));
    });

    test('uscito nel frattempo: il risultato non si applica', () async {
      await signIn();
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
      await signIn();
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
      await signIn();
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
      await signIn();
      when(() => auth.currentUser())
          .thenThrow(const ServerUnreachableException());
      await controller().refreshUser();

      when(() => auth.currentUser()).thenAnswer((_) async => testUser);
      await controller().refreshUser();

      expect((state() as SessionSignedIn).user.isAdministrator, isFalse);
    });
  });
}
