import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/auth_service.dart';

import '../../support/fake_adapter.dart';
import '../../support/profile_fakes.dart';
import '../../support/test_data.dart';

class MockAuthApi extends Mock implements AuthApi {}

/// Uno storage che non riesce a salvare i profili.
class _UnwritableProfileStore implements ProfileStore {
  @override
  Future<ProfileBook> read() async => const ProfileBook();

  @override
  Future<void> write(ProfileBook book) async =>
      throw StateError('scrittura fallita');
}

void main() {
  late MockAuthApi api;
  late MockAuthApi revokeApi;
  late JellyfinHttp http;
  late MemoryProfileStore store;
  late AuthService service;

  /// Le credenziali dei client passati ad `apiFor`: i token annullati.
  late List<(String?, String)> revoked;
  late int newDeviceIds;

  final mario = testProfile(userId: 'u1', name: 'Mario');
  final luigi = testProfile(userId: 'u2', name: 'Luigi');
  final now = DateTime.utc(2026, 10, 8, 20);

  ProfileBook bookOf(List<StoredProfile> profiles) =>
      profiles.fold(const ProfileBook(), (book, p) => book.upsert(p));

  setUp(() {
    api = MockAuthApi();
    revokeApi = MockAuthApi();
    when(() => revokeApi.logout()).thenAnswer((_) async {});
    revoked = [];
    newDeviceIds = 0;
    http = JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo);
    store = MemoryProfileStore();
    service = AuthService(
      http: http,
      api: api,
      store: store,
      apiFor: (client) {
        revoked.add((client.token, client.deviceId));
        return revokeApi;
      },
      newDeviceId: () => 'dev-nuovo-${++newDeviceIds}',
    );
  });

  group('restore', () {
    test('nessun profilo: NoStoredSession, nessuna chiamata', () async {
      expect(await service.restore(), isA<NoStoredSession>());
      verifyNever(() => api.getMe());
    });

    test('un profilo valido: le sue credenziali, nome e immagine aggiornati',
        () async {
      store.book = bookOf([mario.copyWith(name: '')]);
      when(() => api.getMe()).thenAnswer((_) async =>
          const JellyfinUser(id: 'u1', name: 'Mario', primaryImageTag: 'img1'));

      final result = await withClock(Clock.fixed(now), service.restore);

      expect((result as RestoredSession).user.name, 'Mario');
      expect(http.token, 'tok-u1');
      expect(http.deviceId, 'dev-u1');
      expect(service.activeUserId, 'u1');
      final saved = store.book.byId('u1')!;
      expect(saved.name, 'Mario');
      expect(saved.imageTag, 'img1');
      expect(saved.lastUsedAt, now);
      expect(store.book.lastUserId, 'u1');
      expect(service.book.byId('u1')!.name, 'Mario');
    });

    test('un profilo scaduto (401): segnato, credenziali tolte', () async {
      store.book = bookOf([mario]);
      when(() => api.getMe()).thenThrow(const UnauthorizedException());

      final result = await service.restore();

      expect((result as StoredSessionExpired).userId, 'u1');
      expect(store.book.byId('u1')!.expired, isTrue);
      expect(http.token, isNull);
      expect(http.deviceId, 'dev-test');
      expect(service.activeUserId, isNull);
    });

    test('un profilo e server giù: irraggiungibile, profilo intatto', () async {
      store.book = bookOf([mario]);
      when(() => api.getMe()).thenThrow(const ServerUnreachableException());

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(store.book.byId('u1')!.expired, isFalse);
      expect(http.token, isNull);
    });

    test('errore 500: come irraggiungibile, profilo intatto', () async {
      store.book = bookOf([mario]);
      when(() => api.getMe()).thenThrow(const ServerErrorException(500));

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(store.book.byId('u1')!.accessToken, 'tok-u1');
    });

    test('due profili: si sceglie, nessuna chiamata', () async {
      store.book = bookOf([mario, luigi]);
      expect(await service.restore(), isA<ChooseProfile>());
      verifyNever(() => api.getMe());
      expect(service.book.profiles, hasLength(2));
    });
  });

  group('openProfile', () {
    setUp(() async {
      store.book = bookOf([mario, luigi]);
      await service.restore();
    });

    test('apre il profilo scelto con le sue credenziali', () async {
      when(() => api.getMe()).thenAnswer(
          (_) async => const JellyfinUser(id: 'u2', name: 'Luigi'));

      final result = await service.openProfile('u2');

      expect((result as RestoredSession).user.id, 'u2');
      expect(http.token, 'tok-u2');
      expect(http.deviceId, 'dev-u2');
      expect(store.book.lastUserId, 'u2');
    });

    test('un profilo che non c\'è: di nuovo la scelta', () async {
      expect(await service.openProfile('u9'), isA<ChooseProfile>());
      verifyNever(() => api.getMe());
    });
  });

  group('accesso', () {
    test('prepareLogin: un DeviceId nuovo a ogni accesso, nessun token',
        () async {
      store.book = bookOf([mario, luigi]);
      await service.restore();

      service.prepareLogin();
      expect(http.deviceId, 'dev-nuovo-1');
      expect(http.token, isNull);

      service.prepareLogin();
      expect(http.deviceId, 'dev-nuovo-2');
      expect(http.token, isNull);
      expect(service.activeUserId, isNull);
    });

    test('"Accedi di nuovo": DeviceId nuovo, token vecchio annullato con il suo',
        () async {
      store.book = bookOf([mario, luigi.copyWith(expired: true)]);
      await service.restore();
      service.prepareLogin();
      when(() => api.authenticateByName('luigi', 'pw')).thenAnswer((_) async =>
          const AuthResult(
              user: JellyfinUser(id: 'u2', name: 'Luigi'),
              accessToken: 'tok-nuovo'));

      await service.loginWithPassword('luigi', 'pw');

      final saved = store.book.byId('u2')!;
      expect(saved.accessToken, 'tok-nuovo');
      expect(saved.deviceId, 'dev-nuovo-1');
      expect(saved.expired, isFalse);
      expect(http.deviceId, 'dev-nuovo-1');
      // Il token vecchio, con il suo DeviceId: la sessione nuova non c'entra.
      expect(revoked, [('tok-u2', 'dev-u2')]);
    });

    test('"Accedi di nuovo" ma accede un altro utente: tre DeviceId diversi',
        () async {
      store.book = bookOf([mario, luigi.copyWith(expired: true)]);
      await service.restore();
      service.prepareLogin();
      when(() => api.authenticateByName(any(), any())).thenAnswer((_) async =>
          const AuthResult(
              user: JellyfinUser(id: 'u3', name: 'Peach'),
              accessToken: 'tok-u3'));

      await service.loginWithPassword('peach', 'pw');

      expect(store.book.profiles.map((p) => p.deviceId),
          ['dev-u1', 'dev-u2', 'dev-nuovo-1']);
      expect(store.book.byId('u2')!.expired, isTrue);
      expect(revoked, isEmpty);
    });

    test('password: il DeviceId è quello della richiesta, anche se cambia dopo',
        () async {
      service.prepareLogin();
      final answer = Completer<AuthResult>();
      when(() => api.authenticateByName(any(), any()))
          .thenAnswer((_) => answer.future);

      final login = service.loginWithPassword('mario', 'pw');
      service.prepareLogin();
      answer.complete(
          const AuthResult(user: testUser, accessToken: 'tok-nuovo'));
      await login;

      expect(store.book.byId('u1')!.deviceId, 'dev-nuovo-1');
      expect(http.deviceId, 'dev-nuovo-1');
      expect(http.token, 'tok-nuovo');
    });

    test('Quick Connect: il DeviceId è quello della richiesta', () async {
      service.prepareLogin();
      final answer = Completer<AuthResult>();
      when(() => api.authenticateWithQuickConnect('s1'))
          .thenAnswer((_) => answer.future);

      final login = service.completeQuickConnect('s1');
      service.prepareLogin();
      answer.complete(const AuthResult(user: testUser, accessToken: 'tok-qc'));
      await login;

      expect(store.book.byId('u1')!.deviceId, 'dev-nuovo-1');
      expect(http.deviceId, 'dev-nuovo-1');
    });

    test('password: profilo nuovo con il DeviceId dell\'accesso', () async {
      service.prepareLogin();
      when(() => api.authenticateByName('mario', 'pw')).thenAnswer((_) async =>
          const AuthResult(user: testUser, accessToken: 'tok-nuovo'));

      final user = await withClock(
          Clock.fixed(now), () => service.loginWithPassword('  mario ', 'pw'));

      expect(user.id, 'u1');
      final saved = store.book.byId('u1')!;
      expect(saved.accessToken, 'tok-nuovo');
      expect(saved.deviceId, 'dev-nuovo-1');
      expect(saved.name, 'Mario');
      expect(saved.lastUsedAt, now);
      expect(store.book.lastUserId, 'u1');
      expect(http.token, 'tok-nuovo');
      expect(http.deviceId, 'dev-nuovo-1');
      expect(service.activeUserId, 'u1');
      expect(revoked, isEmpty);
    });

    test('stesso utente: un solo profilo, token vecchio annullato', () async {
      store.book = bookOf([mario, luigi]);
      await service.restore();
      service.prepareLogin();
      when(() => api.authenticateByName(any(), any())).thenAnswer((_) async =>
          const AuthResult(user: testUser, accessToken: 'tok-nuovo'));

      await service.loginWithPassword('mario', 'pw');

      expect(store.book.profiles.map((p) => p.userId), ['u1', 'u2']);
      expect(store.book.byId('u1')!.accessToken, 'tok-nuovo');
      // Il token vecchio, con le sue credenziali.
      expect(revoked, [('tok-u1', 'dev-u1')]);
      verify(() => revokeApi.logout()).called(1);
    });

    test('sesto profilo: rifiutato, token nuovo annullato, niente salvato',
        () async {
      store.book = bookOf([
        for (var i = 1; i <= ProfileBook.maxProfiles; i++)
          testProfile(userId: 'u$i'),
      ]);
      await service.restore();
      service.prepareLogin();
      final writes = store.writes;
      when(() => api.authenticateByName(any(), any())).thenAnswer((_) async =>
          const AuthResult(
              user: JellyfinUser(id: 'u9', name: 'Toad'),
              accessToken: 'tok-u9'));

      await expectLater(service.loginWithPassword('toad', 'pw'),
          throwsA(isA<ProfileLimitException>()));

      expect(store.writes, writes);
      expect(store.book.byId('u9'), isNull);
      expect(revoked, [('tok-u9', 'dev-nuovo-1')]);
      expect(service.activeUserId, isNull);
    });

    test('errore del server: niente salvato', () async {
      service.prepareLogin();
      when(() => api.authenticateByName(any(), any()))
          .thenThrow(const UnauthorizedException());

      await expectLater(service.loginWithPassword('mario', 'x'),
          throwsA(isA<UnauthorizedException>()));
      expect(store.book.isEmpty, isTrue);
      expect(store.writes, 0);
    });

    test('Quick Connect: come la password', () async {
      service.prepareLogin();
      when(() => api.authenticateWithQuickConnect('s1')).thenAnswer(
          (_) async => const AuthResult(user: testUser, accessToken: 'tok-qc'));

      await service.completeQuickConnect('s1');

      expect(store.book.byId('u1')!.accessToken, 'tok-qc');
      expect(store.book.byId('u1')!.deviceId, 'dev-nuovo-1');
      expect(http.token, 'tok-qc');
    });

    test('profili non salvati: l\'accesso riesce, il profilo vale per ora',
        () async {
      final unsaved = AuthService(
          http: http, api: api, store: _UnwritableProfileStore());
      when(() => api.authenticateByName('mario', 'pw')).thenAnswer((_) async =>
          const AuthResult(user: testUser, accessToken: 'tok-nuovo'));

      final user = await unsaved.loginWithPassword('mario', 'pw');

      expect(user.id, 'u1');
      expect(unsaved.book.byId('u1')!.accessToken, 'tok-nuovo');
      expect(unsaved.activeUserId, 'u1');
      expect(http.token, 'tok-nuovo');
    });
  });

  group('uscita', () {
    Future<void> openMario() async {
      store.book = bookOf([mario, luigi]);
      await service.restore();
      when(() => api.getMe()).thenAnswer((_) async => testUser);
      await service.openProfile('u1');
    }

    test('logout: token annullato, profilo tolto, id restituito', () async {
      await openMario();
      when(() => api.logout()).thenAnswer((_) async {});

      expect(await service.logout(), 'u1');

      verify(() => api.logout()).called(1);
      expect(store.book.byId('u1'), isNull);
      expect(store.book.byId('u2'), isNotNull);
      expect(http.token, isNull);
      expect(service.activeUserId, isNull);
    });

    test('logout con il server giù: il profilo si toglie lo stesso', () async {
      await openMario();
      when(() => api.logout()).thenThrow(const ServerUnreachableException());

      expect(await service.logout(), 'u1');
      expect(store.book.byId('u1'), isNull);
    });

    test('logout senza profilo attivo: niente', () async {
      expect(await service.logout(), isNull);
      verifyNever(() => api.logout());
    });

    test('removeProfile di un altro profilo: con le sue credenziali', () async {
      await openMario();

      await service.removeProfile('u2');

      expect(revoked, [('tok-u2', 'dev-u2')]);
      expect(store.book.byId('u2'), isNull);
      // Le credenziali attive restano.
      expect(http.token, 'tok-u1');
      expect(service.activeUserId, 'u1');
    });

    test('removeProfile del profilo attivo: come logout', () async {
      await openMario();
      when(() => api.logout()).thenAnswer((_) async {});

      await service.removeProfile('u1');

      verify(() => api.logout()).called(1);
      expect(store.book.byId('u1'), isNull);
      expect(http.token, isNull);
    });

    test('removeProfile con il server giù: il profilo si toglie lo stesso',
        () async {
      await openMario();
      when(() => revokeApi.logout())
          .thenThrow(const ServerUnreachableException());

      await service.removeProfile('u2');
      expect(store.book.byId('u2'), isNull);
    });

    test('removeProfile di un altro profilo: non aspetta il server', () async {
      await openMario();
      // Il server non risponde mai (giù, fino al timeout della connessione).
      final never = Completer<void>();
      when(() => revokeApi.logout()).thenAnswer((_) => never.future);

      var done = false;
      unawaited(service.removeProfile('u2').then((_) => done = true));
      await pumpEventQueue();

      expect(done, isTrue);
      expect(store.book.byId('u2'), isNull);
      expect(revoked, [('tok-u2', 'dev-u2')]);
    });

    test('removeProfile: un errore qualsiasi dell\'annullamento si ignora',
        () async {
      await openMario();
      when(() => revokeApi.logout())
          .thenAnswer((_) async => throw StateError('x'));

      await service.removeProfile('u2');
      // Un errore non gestito farebbe fallire il test.
      await pumpEventQueue();

      expect(store.book.byId('u2'), isNull);
    });

    test('deactivate: credenziali tolte, token salvato', () async {
      await openMario();

      service.deactivate();

      expect(http.token, isNull);
      expect(http.deviceId, 'dev-test');
      expect(service.activeUserId, isNull);
      expect(store.book.byId('u1')!.accessToken, 'tok-u1');
    });

    test('markActiveExpired: il profilo attivo è scaduto', () async {
      await openMario();

      await service.markActiveExpired();

      expect(store.book.byId('u1')!.expired, isTrue);
      expect(http.token, isNull);
      expect(service.activeUserId, isNull);
    });

    test('updateActiveProfile: nome e immagine, solo se cambiano', () async {
      await openMario();
      final writes = store.writes;

      await service.updateActiveProfile(testUser);
      expect(store.writes, writes);

      await service.updateActiveProfile(const JellyfinUser(
          id: 'u1', name: 'Mario Rossi', primaryImageTag: 'img2'));
      expect(store.book.byId('u1')!.name, 'Mario Rossi');
      expect(store.book.byId('u1')!.imageTag, 'img2');

      // Un altro utente non tocca il profilo attivo.
      await service.updateActiveProfile(
          const JellyfinUser(id: 'u2', name: 'Altro'));
      expect(store.book.byId('u2')!.name, 'Luigi');
    });
  });

  test('currentUser rilegge /Users/Me', () async {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);
    when(() => api.getMe(quietStatuses: any(named: 'quietStatuses')))
        .thenAnswer((_) async => admin);

    expect((await service.currentUser()).isAdministrator, isTrue);
    // Durante un riavvio i 502/503/504 sono attesi: nel log come info.
    verify(() => api.getMe(quietStatuses: const {502, 503, 504})).called(1);
  });

  group('log durante un riavvio (AuthApi vero)', () {
    late FakeAdapter adapter;
    late List<LogRecord> records;

    setUp(() {
      records = [];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previousLevel);
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      adapter = FakeAdapter((_) => const FakeResponse(503));
    });

    AuthService realService(MemoryProfileStore store) {
      final realHttp = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
      return AuthService(http: realHttp, api: AuthApi(realHttp), store: store);
    }

    List<(Level, String)> httpLog() => [
          for (final record in records)
            if (record.loggerName == 'http') (record.level, record.message),
        ];

    test('currentUser: 502, 503 e 504 come info, un 500 come avviso',
        () async {
      final service = realService(MemoryProfileStore());
      for (final status in [502, 503, 504, 500]) {
        adapter.handler = (_) => FakeResponse(status);
        await expectLater(
            service.currentUser(), throwsA(isA<ServerErrorException>()));
      }

      expect(httpLog(), [
        (Level.INFO, 'GET /Users/Me: 502'),
        (Level.INFO, 'GET /Users/Me: 503'),
        (Level.INFO, 'GET /Users/Me: 504'),
        (Level.WARNING, 'GET /Users/Me: 500'),
      ]);
    });

    test('il ripristino resta com\'era: un 503 è un avviso', () async {
      final service = realService(MemoryProfileStore(bookOf([mario])));

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(httpLog(), [(Level.WARNING, 'GET /Users/Me: 503')]);
    });
  });
}
