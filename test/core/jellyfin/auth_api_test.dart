import 'package:flutter_test/flutter_test.dart';
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
}
