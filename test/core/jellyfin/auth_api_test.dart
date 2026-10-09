import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late AuthApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = AuthApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('authenticateByName invia Username/Pw e legge token e utente', () async {
    adapter.handler = (_) => FakeResponse(200, authResultJson());

    final result = await api.authenticateByName('mario', 'segreta');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Users/AuthenticateByName');
    expect(request.data, {'Username': 'mario', 'Pw': 'segreta'});
    expect(result.accessToken, 'tok-1');
    expect(result.user.id, 'u1');
    expect(result.user.name, 'Mario');
    expect(result.user.primaryImageTag, 'img1');
  });

  test('getMe legge l\'utente corrente', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Id': 'u1', 'Name': 'Mario'});
    final user = await api.getMe();
    expect(adapter.requests.single.path, '/Users/Me');
    expect(user.name, 'Mario');
    expect(user.primaryImageTag, isNull);
  });

  group('getMe e il log degli stati attesi', () {
    late List<LogRecord> records;

    setUp(() {
      records = [];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previousLevel);
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
    });

    List<(Level, String)> httpLog() => [
          for (final record in records)
            if (record.loggerName == 'http') (record.level, record.message),
        ];

    test('senza stati attesi un 503 è un avviso', () async {
      adapter.handler = (_) => const FakeResponse(503);
      await expectLater(api.getMe(), throwsA(isA<ServerErrorException>()));

      expect(httpLog(), [(Level.WARNING, 'GET /Users/Me: 503')]);
    });

    test('con 502, 503 e 504 attesi vanno nel log come info', () async {
      for (final status in [502, 503, 504]) {
        adapter.handler = (_) => FakeResponse(status);
        await expectLater(
            api.getMe(quietStatuses: const {502, 503, 504}),
            throwsA(isA<ServerErrorException>()));
      }

      expect(httpLog(), [
        (Level.INFO, 'GET /Users/Me: 502'),
        (Level.INFO, 'GET /Users/Me: 503'),
        (Level.INFO, 'GET /Users/Me: 504'),
      ]);
    });

    test('un 500 resta un avviso anche con gli stati attesi', () async {
      adapter.handler = (_) => const FakeResponse(500);
      await expectLater(api.getMe(quietStatuses: const {502, 503, 504}),
          throwsA(isA<ServerErrorException>()));

      expect(httpLog(), [(Level.WARNING, 'GET /Users/Me: 500')]);
    });
  });

  test('getMe con corpo malformato lancia ServerErrorException', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Id': 1});
    await expectLater(api.getMe(), throwsA(isA<ServerErrorException>()));
  });

  test('logout chiama POST /Sessions/Logout', () async {
    await api.logout();
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/Sessions/Logout');
  });

  test('quickConnectEnabled legge il booleano', () async {
    adapter.handler = (_) => const FakeResponse(200, true);
    expect(await api.quickConnectEnabled(), isTrue);
    adapter.handler = (_) => const FakeResponse(200, false);
    expect(await api.quickConnectEnabled(), isFalse);
  });

  test('initiateQuickConnect restituisce codice e segreto', () async {
    adapter.handler = (_) => const FakeResponse(200,
        {'Code': '482913', 'Secret': 's1', 'Authenticated': false});
    final state = await api.initiateQuickConnect();
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/QuickConnect/Initiate');
    expect(state.code, '482913');
    expect(state.secret, 's1');
    expect(state.authenticated, isFalse);
  });

  test('quickConnectState passa il segreto in query', () async {
    adapter.handler = (_) => const FakeResponse(200,
        {'Code': '482913', 'Secret': 's1', 'Authenticated': true});
    final state = await api.quickConnectState('s1');
    expect(adapter.requests.single.path, '/QuickConnect/Connect');
    expect(adapter.requests.single.queryParameters, {'secret': 's1'});
    expect(state.authenticated, isTrue);
  });

  test('authenticateWithQuickConnect invia il segreto', () async {
    adapter.handler = (_) => FakeResponse(200, authResultJson(token: 'tok-qc'));
    final result = await api.authenticateWithQuickConnect('s1');
    expect(adapter.requests.single.path, '/Users/AuthenticateWithQuickConnect');
    expect(adapter.requests.single.data, {'Secret': 's1'});
    expect(result.accessToken, 'tok-qc');
  });

  test('changePassword: POST /Users/Password con la password attuale',
      () async {
    await api.changePassword('u1',
        currentPassword: 'vecchia', newPassword: 'nuova123');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Users/Password');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(request.data, {'CurrentPw': 'vecchia', 'NewPw': 'nuova123'});
  });

  test("changePassword senza la password attuale (l'admin, piano 18c)",
      () async {
    await api.changePassword('u2', newPassword: 'nuova123');
    expect(adapter.requests.single.data, {'NewPw': 'nuova123'});
  });

  test('changePassword: 403 con la password sbagliata, nel log come info',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    adapter.handler = (_) => const FakeResponse(403);

    await expectLater(
        api.changePassword('u1', currentPassword: 'x', newPassword: 'nuova123'),
        throwsA(isA<ForbiddenException>()));

    expect(records.where((r) => r.loggerName == 'http').single.level,
        Level.INFO);
  });
}
