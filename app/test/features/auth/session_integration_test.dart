import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_adapter.dart';
import '../../support/profile_fakes.dart';
import '../../support/test_data.dart';

/// La sessione con i pezzi veri (`SessionController`, `AuthService`,
/// `AuthApi`, `JellyfinHttp`): finti solo la rete e lo storage.
void main() {
  late FakeAdapter adapter;
  late JellyfinHttp http;
  late MemoryProfileStore store;
  late ProviderContainer container;

  /// Gli stati della sessione, nell'ordine.
  late List<SessionState> states;

  SessionController controller() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);

  Matcher reloginFor(String userId) => isA<SessionSignedOut>()
      .having((s) => s.expired, 'expired', true)
      .having((s) => s.reloginUserId, 'reloginUserId', userId);

  /// `/Users/Me` risponde Mario; tutto il resto 401.
  FakeResponse marioThenUnauthorized(RequestOptions options) =>
      options.path == '/Users/Me'
          ? const FakeResponse(200, {'Id': 'u1', 'Name': 'Mario'})
          : const FakeResponse(401);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    adapter = FakeAdapter((_) => const FakeResponse(204));
    http = JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
    store = MemoryProfileStore(const ProfileBook()
        .upsert(testProfile(userId: 'u1', name: 'Mario'))
        .upsert(testProfile(userId: 'u2', name: 'Luigi')));
    container = ProviderContainer.test(
      overrides: [
        jellyfinHttpProvider.overrideWithValue(http),
        profileStoreProvider.overrideWithValue(store),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      retry: (_, _) => null,
    );
    states = [];
    container.listen(sessionControllerProvider, (_, next) => states.add(next));
    await controller().restore();
    expect(state(), isA<SessionChoosingProfile>());
  });

  test('un 401 di /Users/Me aprendo un profilo: un solo accesso, segnato '
      'una volta', () async {
    adapter.handler = (_) => const FakeResponse(401);
    final writes = store.writes;

    await controller().openProfile('u2');

    expect(state(), reloginFor('u2'));
    expect(states.whereType<SessionSignedOut>(), hasLength(1));
    expect(store.writes, writes + 1);
    expect(store.book.byId('u2')!.expired, isTrue);
    expect(http.token, isNull);
  });

  test('un 401 durante la sessione: accesso per quel profilo, scaduto',
      () async {
    adapter.handler = marioThenUnauthorized;
    await controller().openProfile('u1');
    expect((state() as SessionSignedIn).user.id, 'u1');

    await expectLater(
        http.get('/Users/u1/Items'), throwsA(isA<UnauthorizedException>()));
    // Il profilo si segna senza che la sessione lo aspetti.
    await pumpEventQueue();

    expect(state(), reloginFor('u1'));
    expect(states.whereType<SessionSignedOut>(), hasLength(1));
    expect(store.book.byId('u1')!.expired, isTrue);
    expect(container.read(profilesProvider).book.byId('u1')!.expired, isTrue);
    expect(http.token, isNull);
  });

  group('un accesso che finisce dopo "Annulla", mentre si apre Luigi', () {
    late Completer<FakeResponse> login;
    late Completer<FakeResponse> luigiMe;
    late Future<void> signingIn;
    late Future<void> opening;

    setUp(() async {
      login = Completer<FakeResponse>();
      luigiMe = Completer<FakeResponse>();
      adapter.handler = (options) {
        if (options.path == '/Users/AuthenticateByName') return login.future;
        if (options.path == '/Users/Me') return luigiMe.future;
        return const FakeResponse(204);
      };
      // "Aggiungi profilo", la password, "Annulla", poi Luigi in "Chi
      // guarda?": il server non ha ancora risposto a nessuno dei due.
      controller().addProfile();
      controller().prepareLogin();
      signingIn = controller().loginWithPassword('peach', 'pw');
      await pumpEventQueue();
      controller().cancelLogin();
      opening = controller().openProfile('u2');
      await pumpEventQueue();
    });

    void answerLogin() => login.complete(const FakeResponse(200, {
          'User': {'Id': 'u3', 'Name': 'Peach'},
          'AccessToken': 'tok-u3',
          'ServerId': 'srv',
        }));

    void answerLuigi() => luigiMe
        .complete(const FakeResponse(200, {'Id': 'u2', 'Name': 'Luigi'}));

    void expectLuigiOpen() {
      expect((state() as SessionSignedIn).user.id, 'u2');
      expect(http.token, 'tok-u2');
      expect(http.deviceId, 'dev-u2');
      final profiles = container.read(profilesProvider);
      expect(profiles.activeUserId, 'u2');
      // Il profilo nuovo è salvato e compare in "Chi guarda?".
      expect(profiles.book.byId('u3')!.accessToken, 'tok-u3');
      expect(store.book.byId('u3'), isNotNull);
      expect(store.book.lastUserId, 'u2');
    }

    test('prima la password, poi Luigi', () async {
      answerLogin();
      await signingIn;
      expect(state(), isA<SessionChoosingProfile>());
      expect(container.read(profilesProvider).book.byId('u3'), isNotNull);

      answerLuigi();
      await opening;

      expectLuigiOpen();
    });

    test('prima Luigi, poi la password', () async {
      answerLuigi();
      await opening;
      answerLogin();
      await signingIn;

      expectLuigiOpen();
    });
  });

  test('un 401 della richiesta di uscita: si esce e basta', () async {
    adapter.handler = marioThenUnauthorized;
    await controller().openProfile('u1');

    await controller().logout();

    expect(adapter.requests.last.path, '/Sessions/Logout');
    expect(state(), isA<SessionChoosingProfile>());
    expect(states.whereType<SessionSignedOut>(), isEmpty);
    expect(store.book.byId('u1'), isNull);
    expect(store.book.byId('u2'), isNotNull);
    expect(http.token, isNull);
  });
}
