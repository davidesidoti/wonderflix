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
          '/System/Info/Public' => const FakeResponse(
              200, {'Version': '10.11.9', 'StartupWizardCompleted': true}),
          '/System/Restart' => const FakeResponse(204),
          '/Library/VirtualFolders' => FakeResponse(200, librariesJson),
          '/ScheduledTasks' => FakeResponse(200, tasksJson),
          '/System/ActivityLog/Entries' => FakeResponse(200, activityJson),
          final path when path.startsWith('/Items/') ||
              path.startsWith('/ScheduledTasks/Running/') =>
            const FakeResponse(204),
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

    test('risponde ma il setup non è finito: giù', () async {
      // Jellyfin 10.11 avvia prima un server di setup, 6-18 s prima di
      // quello vero, e quello risponde 200 a /System/Info/Public.
      adapter.handler = (_) => const FakeResponse(
          200, {'Version': '10.11.9', 'StartupWizardCompleted': false});
      expect(await api.isServerUp(), isFalse);
    });

    test('risponde senza StartupWizardCompleted: giù', () async {
      adapter.handler = (_) => const FakeResponse(200, {'Version': '10.11.9'});
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (_) => const FakeResponse(
          200, {'StartupWizardCompleted': 'true'});
      expect(await api.isServerUp(), isFalse,
          reason: 'solo il booleano vero conta');
    });

    test('risponde con un corpo che non è un oggetto: giù', () async {
      adapter.handler = (_) => const FakeResponse(200, ['StartupWizardCompleted']);
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (_) => const FakeResponse(200, 'true');
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (_) => const FakeResponse(200, true);
      expect(await api.isServerUp(), isFalse);
      adapter.handler = (_) => const FakeResponse(204);
      expect(await api.isServerUp(), isFalse);
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

    test('502, 503 e 504 del POST di riavvio vanno nel log come info',
        () async {
      for (final status in [502, 503, 504]) {
        adapter.handler = (_) => FakeResponse(status);
        await expectLater(
            api.restart(), throwsA(isA<ServerErrorException>()));
      }

      expect(httpLog(), [
        (Level.INFO, 'POST /System/Restart: 502'),
        (Level.INFO, 'POST /System/Restart: 503'),
        (Level.INFO, 'POST /System/Restart: 504'),
      ]);
    });

    test('un 500 sul POST di riavvio resta un avviso', () async {
      adapter.handler = (_) => const FakeResponse(500);
      await expectLater(api.restart(), throwsA(isA<ServerErrorException>()));

      expect(httpLog(), [(Level.WARNING, 'POST /System/Restart: 500')]);
    });
  });

  group('manutenzione', () {
    test('librerie', () async {
      final libraries = await api.libraries();
      expect(libraries, hasLength(4));
      expect(adapter.requests.single.path, '/Library/VirtualFolders');
    });

    test('scansiona una libreria come la Dashboard web', () async {
      await api.scanLibrary('a656b907eb3a73532e40e44b968d0225');
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/Items/a656b907eb3a73532e40e44b968d0225/Refresh');
      expect(request.queryParameters, {
        'Recursive': true,
        'ImageRefreshMode': 'Default',
        'MetadataRefreshMode': 'Default',
        'ReplaceAllImages': false,
        'RegenerateTrickplay': false,
        'ReplaceAllMetadata': false,
      });
      // Com'è davvero sul filo: booleani minuscoli, come li legge Jellyfin.
      expect(request.uri.query, contains('Recursive=true'));
      expect(request.uri.query, contains('ReplaceAllImages=false'));
    });

    test('attività visibili', () async {
      final tasks = await api.tasks();
      expect(tasks, hasLength(8));
      expect(adapter.requests.single.path, '/ScheduledTasks');
      expect(adapter.requests.single.queryParameters, {'isHidden': false});
    });

    test('avvia e ferma', () async {
      await api.startTask('t-scan');
      await api.stopTask('t-scan');
      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'POST /ScheduledTasks/Running/t-scan',
        'DELETE /ScheduledTasks/Running/t-scan',
      ]);
    });
  });

  group('registro', () {
    test('pagina da 50, tutto', () async {
      final page = await api.activity(startIndex: 0);
      expect(page.items, hasLength(5));
      expect(page.total, 12134);
      final request = adapter.requests.single;
      expect(request.path, '/System/ActivityLog/Entries');
      expect(request.queryParameters, {'startIndex': 0, 'limit': 50});
    });

    test('filtro utenti o sistema', () async {
      await api.activity(startIndex: 50, hasUserId: true);
      await api.activity(startIndex: 0, hasUserId: false);
      expect(adapter.requests[0].queryParameters,
          {'startIndex': 50, 'limit': 50, 'hasUserId': true});
      expect(adapter.requests[1].queryParameters,
          {'startIndex': 0, 'limit': 50, 'hasUserId': false});
    });
  });
}
