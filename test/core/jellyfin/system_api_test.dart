import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/system_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SystemApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {
          'Version': '10.11.9',
          'ServerName': 'casa',
        }));
    api = SystemApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('serverVersion legge /System/Info/Public', () async {
    expect(await api.serverVersion(), '10.11.9');
    expect(adapter.requests.single.path, '/System/Info/Public');
  });

  test('risposta senza versione: errore del server', () async {
    adapter.handler = (_) => const FakeResponse(200, {'ServerName': 'casa'});
    await expectLater(
        api.serverVersion(), throwsA(isA<ServerErrorException>()));
  });
}
