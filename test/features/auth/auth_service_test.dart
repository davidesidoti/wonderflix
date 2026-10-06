import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/storage/session_store.dart';
import 'package:wonderflix/features/auth/auth_service.dart';

import '../../support/fake_adapter.dart';
import '../../support/memory_session_store.dart';
import '../../support/test_data.dart';

class MockAuthApi extends Mock implements AuthApi {}

void main() {
  late MockAuthApi api;
  late JellyfinHttp http;
  late MemorySessionStore store;
  late AuthService service;

  const stored = StoredSession(userId: 'u1', accessToken: 'tok-old');

  setUp(() {
    api = MockAuthApi();
    http = JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo);
    store = MemorySessionStore();
    service = AuthService(http: http, api: api, store: store);
  });

  group('restore', () {
    test('nessuna sessione salvata', () async {
      expect(await service.restore(), isA<NoStoredSession>());
      verifyNever(() => api.getMe());
    });

    test('token valido: imposta il token e restituisce l\'utente', () async {
      store.session = stored;
      when(() => api.getMe()).thenAnswer((_) async => testUser);

      final result = await service.restore();

      expect(result, isA<RestoredSession>());
      expect((result as RestoredSession).user.name, 'Mario');
      expect(http.token, 'tok-old');
    });

    test('401: cancella la sessione', () async {
      store.session = stored;
      when(() => api.getMe()).thenThrow(const UnauthorizedException());

      expect(await service.restore(), isA<StoredSessionExpired>());
      expect(store.session, isNull);
      expect(http.token, isNull);
    });

    test('server irraggiungibile: mantiene la sessione', () async {
      store.session = stored;
      when(() => api.getMe()).thenThrow(const ServerUnreachableException());

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(store.session, isNotNull);
    });

    test('errore 500: trattato come irraggiungibile, mantiene la sessione',
        () async {
      store.session = stored;
      when(() => api.getMe()).thenThrow(const ServerErrorException(500));

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(store.session, isNotNull);
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
    late AuthService realService;
    late List<LogRecord> records;

    setUp(() {
      records = [];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previousLevel);
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      adapter = FakeAdapter((_) => const FakeResponse(503));
      final realHttp = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
      realService = AuthService(
          http: realHttp, api: AuthApi(realHttp), store: MemorySessionStore());
    });

    List<(Level, String)> httpLog() => [
          for (final record in records)
            if (record.loggerName == 'http') (record.level, record.message),
        ];

    test('currentUser: 502, 503 e 504 come info, un 500 come avviso',
        () async {
      for (final status in [502, 503, 504, 500]) {
        adapter.handler = (_) => FakeResponse(status);
        await expectLater(realService.currentUser(),
            throwsA(isA<ServerErrorException>()));
      }

      expect(httpLog(), [
        (Level.INFO, 'GET /Users/Me: 502'),
        (Level.INFO, 'GET /Users/Me: 503'),
        (Level.INFO, 'GET /Users/Me: 504'),
        (Level.WARNING, 'GET /Users/Me: 500'),
      ]);
    });

    test('il ripristino della sessione resta com\'era: un 503 è un avviso',
        () async {
      final store = MemorySessionStore()..session = stored;
      final realHttp = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
      final restoring =
          AuthService(http: realHttp, api: AuthApi(realHttp), store: store);

      expect(await restoring.restore(), isA<RestoreServerUnreachable>());
      expect(httpLog(), [(Level.WARNING, 'GET /Users/Me: 503')]);
    });
  });

  test('loginWithPassword salva la sessione e imposta il token', () async {
    when(() => api.authenticateByName('mario', 'pw')).thenAnswer((_) async =>
        const AuthResult(user: testUser, accessToken: 'tok-new'));

    final user = await service.loginWithPassword('  mario ', 'pw');

    expect(user.id, 'u1');
    expect(http.token, 'tok-new');
    expect(store.session?.accessToken, 'tok-new');
  });

  test('loginWithPassword propaga gli errori senza salvare nulla', () async {
    when(() => api.authenticateByName(any(), any()))
        .thenThrow(const UnauthorizedException());

    await expectLater(service.loginWithPassword('mario', 'x'),
        throwsA(isA<UnauthorizedException>()));
    expect(store.session, isNull);
  });

  test('completeQuickConnect salva la sessione', () async {
    when(() => api.authenticateWithQuickConnect('s1')).thenAnswer((_) async =>
        const AuthResult(user: testUser, accessToken: 'tok-qc'));

    await service.completeQuickConnect('s1');

    expect(http.token, 'tok-qc');
    expect(store.session?.accessToken, 'tok-qc');
  });

  test('logout cancella la sessione anche se il server fallisce', () async {
    store.session = stored;
    http.token = 'tok-old';
    when(() => api.logout()).thenThrow(const ServerUnreachableException());

    await service.logout();

    expect(store.session, isNull);
    expect(http.token, isNull);
  });

  test('clearLocalSession cancella senza chiamare il server', () async {
    store.session = stored;
    http.token = 'tok-old';

    await service.clearLocalSession();

    expect(store.session, isNull);
    expect(http.token, isNull);
    verifyNever(() => api.logout());
  });
}
