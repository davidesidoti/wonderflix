import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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

    test('504, nessuna connessione, timeout, 404: giù', () async {
      adapter.handler = (_) => const FakeResponse(504);
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (_) => throw const SocketException('refused');
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (options) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 10), requestOptions: options);
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (_) => const FakeResponse(404);
      expect(await api.isServerUp(), isFalse,
          reason: 'qualunque errore del server vale come giù');
    });
  });

  group('durante un riavvio', () {
    late List<LogRecord> records;

    setUp(() {
      records = [];
      Logger.root.level = Level.ALL;
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
    });

    List<(Level, String)> httpLog() => [
          for (final record in records)
            if (record.loggerName == 'http') (record.level, record.message),
        ];

    test('502, 503 e 504 delle letture vanno nel log come info', () async {
      adapter.handler = (_) => const FakeResponse(503);
      await expectLater(
          api.sessions(), throwsA(isA<ServerErrorException>()));
      adapter.handler = (_) => const FakeResponse(502);
      await expectLater(
          api.partyGroups(), throwsA(isA<ServerErrorException>()));
      adapter.handler = (_) => const FakeResponse(504);
      await expectLater(
          api.serverInfo(), throwsA(isA<ServerErrorException>()));

      expect(httpLog(), [
        (Level.INFO, 'GET /Sessions: 503'),
        (Level.INFO, 'GET /SyncPlay/List: 502'),
        (Level.INFO, 'GET /System/Info: 504'),
      ]);
    });

    test('un 500 resta un avviso', () async {
      adapter.handler = (_) => const FakeResponse(500);
      await expectLater(
          api.sessions(), throwsA(isA<ServerErrorException>()));

      expect(httpLog(), [(Level.WARNING, 'GET /Sessions: 500')]);
    });
  });
}
