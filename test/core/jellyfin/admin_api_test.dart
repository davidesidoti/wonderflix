import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_api.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/admin_json.dart';
import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late AdminApi api;

  setUp(() {
    adapter = FakeAdapter((options) => switch (options.path) {
          '/Sessions' => FakeResponse(200, sessionsJson),
          '/SyncPlay/List' => FakeResponse(200, partyGroupsJson),
          '/System/Info' => FakeResponse(200, serverInfoJson),
          '/System/Info/Public' =>
            const FakeResponse(200, {'Version': '10.11.9'}),
          '/System/Restart' => const FakeResponse(204),
          _ => const FakeResponse(404),
        });
    api = AdminApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('sessioni attive negli ultimi 16 minuti, come la Dashboard', () async {
    final sessions = await api.sessions();

    expect(sessions, hasLength(3));
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/Sessions');
    expect(request.queryParameters, {'activeWithinSeconds': 960});
  });

  test('watch party', () async {
    final groups = await api.partyGroups();
    expect(groups.single.name, 'Serata Lost');
    expect(adapter.requests.single.path, '/SyncPlay/List');
  });

  test('informazioni sul server', () async {
    final info = await api.serverInfo();
    expect(info.version, '10.11.9');
    expect(adapter.requests.single.path, '/System/Info');
  });

  test('un 403 arriva com\'è', () async {
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(api.sessions(), throwsA(isA<ForbiddenException>()));
  });

  test('riavvio', () async {
    await api.restart();
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/System/Restart');
  });

  group('isServerUp', () {
    test('risponde: su', () async {
      expect(await api.isServerUp(), isTrue);
      expect(adapter.requests.single.path, '/System/Info/Public');
    });

    test('502 o 503 di nginx durante il riavvio: giù', () async {
      adapter.handler = (_) => const FakeResponse(503);
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (_) => const FakeResponse(502);
      expect(await api.isServerUp(), isFalse);
    });

    test('nessuna connessione: giù', () async {
      adapter.handler = (_) => throw const SocketException('refused');
      expect(await api.isServerUp(), isFalse);
    });
  });
}
