import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/plugin_admin_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late PluginAdminApi api;

  /// La configurazione vera del plugin (senza i valori di Seerr) più una
  /// chiave che l'app non conosce.
  Map<String, dynamic> config() => {
        'NotifyNewTitles': true,
        'SeerrUrl': 'https://seerr.example.com',
        'SeerrApiKey': 'chiave',
        'SeerrWebhookSecret': 'segreto',
        'Nuova': [1, 2],
      };

  setUp(() {
    adapter = FakeAdapter((options) => switch (options.path) {
          '/WonderFlixWatchParty/Inbox/Announcements' =>
            const FakeResponse(200, {'Recipients': 12}),
          '/WonderFlixWatchParty/Inbox/NewTitles' =>
            const FakeResponse(200, {'Enabled': true, 'Pending': 3}),
          '/WonderFlixWatchParty/Inbox/NewTitles/Send' =>
            const FakeResponse(200, {'Titles': 3, 'Recipients': 12}),
          '/WonderFlixWatchParty/Requests/Admin' => const FakeResponse(200, {
              'Configured': true,
              'LastEventAt': '2026-10-05T17:47:00+00:00',
              'LastEventType': 'TEST_NOTIFICATION',
            }),
          '/WonderFlixWatchParty/Requests/Test' => const FakeResponse(
              200, {'Ok': true, 'Version': '3.4.1', 'Error': null}),
          '/Plugins/882eb47e-668a-4935-ba55-c2858eb4ed90/Configuration' =>
            options.method == 'GET'
                ? FakeResponse(200, config())
                : const FakeResponse(204),
          _ => const FakeResponse(404),
        });
    api = PluginAdminApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('annuncio', () async {
    expect(await api.announce('Ciao a tutti'), 12);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.data, {'Text': 'Ciao a tutti'});
  });

  test('annuncio non valido: 400', () async {
    adapter.handler = (_) => const FakeResponse(400);
    await expectLater(api.announce('x'),
        throwsA(isA<ServerErrorException>().having((e) => e.statusCode, 'status', 400)));
  });

  test('novità e "Invia ora"', () async {
    final status = await api.newTitles();
    expect(status.enabled, isTrue);
    expect(status.pending, 3);
    final sent = await api.sendNewTitles();
    expect(sent.titles, 3);
    expect(sent.recipients, 12);
    expect(adapter.requests.last.method, 'POST');
  });

  test('stato di Seerr; plugin vecchio (404) → null', () async {
    final status = (await api.seerrStatus())!;
    expect(status.configured, isTrue);
    expect(status.lastEventAt, DateTime.utc(2026, 10, 5, 17, 47));
    expect(status.lastEventType, 'TEST_NOTIFICATION');

    adapter.handler = (_) => const FakeResponse(404);
    expect(await api.seerrStatus(), isNull);
  });

  test('prova di Seerr', () async {
    final result = await api.testSeerr();
    expect(result.ok, isTrue);
    expect(result.version, '3.4.1');
    expect(result.error, isNull);

    adapter.handler = (_) =>
        const FakeResponse(200, {'Ok': false, 'Version': null, 'Error': 'SeerrAuth'});
    final failed = await api.testSeerr();
    expect(failed.ok, isFalse);
    expect(failed.error, 'SeerrAuth');
  });

  test('interruttore delle novità: cambia solo NotifyNewTitles', () async {
    await api.setNotifyNewTitles(false);

    expect(adapter.requests.map((r) => r.method), ['GET', 'POST']);
    final written = adapter.requests.last.data as Map<String, dynamic>;
    expect(written, {...config(), 'NotifyNewTitles': false});
  });

  test('un 403 arriva com\'è', () async {
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(api.newTitles(), throwsA(isA<ForbiddenException>()));
  });

  group('risposte malformate: errore, non valori inventati', () {
    Future<void> expectServerError(
        Future<Object?> Function() call, List<Object?> bodies) async {
      for (final body in bodies) {
        adapter.handler = (_) => FakeResponse(200, body);
        await expectLater(call(), throwsA(isA<ServerErrorException>()),
            reason: 'corpo: $body');
      }
    }

    test('stato delle novità: Enabled e Pending sono obbligatori', () async {
      await expectServerError(api.newTitles, [
        <String, Object?>{'Pending': 3},
        {'Enabled': 'true', 'Pending': 3},
        {'Enabled': true},
        {'Enabled': true, 'Pending': '3'},
        {'Enabled': true, 'Pending': null},
        {'Enabled': true, 'Pending': 2.5},
        <String, Object?>{},
        ['Enabled'],
        null,
      ]);
    });

    test('"Invia ora": Titles e Recipients sono obbligatori', () async {
      await expectServerError(api.sendNewTitles, [
        <String, Object?>{'Recipients': 12},
        {'Titles': 3},
        {'Titles': '3', 'Recipients': 12},
        {'Titles': 3, 'Recipients': null},
        {'Titles': 3.5, 'Recipients': 12},
        <String, Object?>{},
        [3, 12],
        null,
      ]);
    });

    test('annuncio: Recipients è obbligatorio', () async {
      await expectServerError(() => api.announce('x'), [
        <String, Object?>{},
        {'Recipients': '12'},
        null,
      ]);
    });

    test('stato di Seerr: Configured è obbligatorio', () async {
      await expectServerError(api.seerrStatus, [
        <String, Object?>{'LastEventType': 'MEDIA_PENDING'},
        {'Configured': 'true'},
        {'Configured': 1},
        {'Configured': null},
        <String, Object?>{},
        ['Configured'],
        null,
      ]);

      // Il resto è facoltativo.
      adapter.handler = (_) => const FakeResponse(200, {'Configured': false});
      final status = (await api.seerrStatus())!;
      expect(status.configured, isFalse);
      expect(status.lastEventAt, isNull);
      expect(status.lastEventType, isNull);

      // Un plugin più vecchio della 1.4.0 non ha l'endpoint: resta null.
      adapter.handler = (_) => const FakeResponse(404);
      expect(await api.seerrStatus(), isNull);
    });

    test('prova di Seerr: Ok è obbligatorio', () async {
      await expectServerError(api.testSeerr, [
        <String, Object?>{'Version': '3.4.1'},
        {'Ok': 'true', 'Version': '3.4.1'},
        {'Ok': 1},
        {'Ok': null, 'Error': 'SeerrAuth'},
        <String, Object?>{},
        [true],
        null,
      ]);

      // Il resto è facoltativo.
      adapter.handler = (_) => const FakeResponse(200, {'Ok': false});
      final result = await api.testSeerr();
      expect(result.ok, isFalse);
      expect(result.version, isNull);
      expect(result.error, isNull);
    });

    test('risposte giuste: zero è un valore vero', () async {
      adapter.handler = (_) =>
          const FakeResponse(200, {'Enabled': false, 'Pending': 0});
      final status = await api.newTitles();
      expect(status.enabled, isFalse);
      expect(status.pending, 0);

      adapter.handler =
          (_) => const FakeResponse(200, {'Titles': 0, 'Recipients': 0});
      final sent = await api.sendNewTitles();
      expect(sent.titles, 0);
      expect(sent.recipients, 0);
    });
  });

  group('interruttore con Jellyfin che si riavvia: nel log', () {
    const path = '/Plugins/882eb47e-668a-4935-ba55-c2858eb4ed90/Configuration';
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

    test('502, 503 e 504 della lettura della configurazione: info', () async {
      for (final status in [502, 503, 504]) {
        adapter.handler = (_) => FakeResponse(status);
        await expectLater(api.setNotifyNewTitles(false),
            throwsA(isA<ServerErrorException>()));
      }

      expect(httpLog(), [
        (Level.INFO, 'GET $path: 502'),
        (Level.INFO, 'GET $path: 503'),
        (Level.INFO, 'GET $path: 504'),
      ]);
    });

    test('502, 503 e 504 della scrittura della configurazione: info', () async {
      for (final status in [502, 503, 504]) {
        adapter.handler = (options) => options.method == 'GET'
            ? FakeResponse(200, config())
            : FakeResponse(status);
        await expectLater(api.setNotifyNewTitles(false),
            throwsA(isA<ServerErrorException>()));
      }

      expect(httpLog(), [
        (Level.INFO, 'POST $path: 502'),
        (Level.INFO, 'POST $path: 503'),
        (Level.INFO, 'POST $path: 504'),
      ]);
    });

    test('un 500 resta un avviso, in lettura e in scrittura', () async {
      adapter.handler = (_) => const FakeResponse(500);
      await expectLater(api.setNotifyNewTitles(false),
          throwsA(isA<ServerErrorException>()));
      adapter.handler = (options) => options.method == 'GET'
          ? FakeResponse(200, config())
          : const FakeResponse(500);
      await expectLater(api.setNotifyNewTitles(false),
          throwsA(isA<ServerErrorException>()));

      expect(httpLog(), [
        (Level.WARNING, 'GET $path: 500'),
        (Level.WARNING, 'POST $path: 500'),
      ]);
    });
  });

  group('interruttore: la configurazione non si riscrive se non torna', () {
    /// Risponde alla lettura con [body] e a ogni altra richiesta con 204.
    void configIs(Object? body) {
      adapter.handler = (options) =>
          options.method == 'GET' ? FakeResponse(200, body) : const FakeResponse(204);
    }

    test('senza NotifyNewTitles: errore e nessuna scrittura', () async {
      configIs({...config()}..remove('NotifyNewTitles'));
      await expectLater(api.setNotifyNewTitles(true),
          throwsA(isA<ServerErrorException>()));
      expect(adapter.requests.map((r) => r.method), ['GET']);
    });

    test('NotifyNewTitles che non è un booleano: nessuna scrittura', () async {
      configIs({...config(), 'NotifyNewTitles': 'true'});
      await expectLater(api.setNotifyNewTitles(false),
          throwsA(isA<ServerErrorException>()));
      expect(adapter.requests.map((r) => r.method), ['GET']);
    });

    test('senza SeerrApiKey: errore e nessuna scrittura', () async {
      // Una POST di una mappa parziale riporterebbe ai valori di default le
      // chiavi mancanti (URL, chiave e segreto di Seerr).
      configIs({...config()}..remove('SeerrApiKey'));
      await expectLater(api.setNotifyNewTitles(false),
          throwsA(isA<ServerErrorException>()));
      expect(adapter.requests.map((r) => r.method), ['GET']);
    });

    test('corpo che non è un oggetto: nessuna scrittura', () async {
      configIs(['NotifyNewTitles']);
      await expectLater(api.setNotifyNewTitles(false),
          throwsA(isA<ServerErrorException>()));
      expect(adapter.requests.map((r) => r.method), ['GET']);
    });

    test('lettura che dà 500: nessuna scrittura', () async {
      adapter.handler = (_) => const FakeResponse(500);
      await expectLater(api.setNotifyNewTitles(false),
          throwsA(isA<ServerErrorException>()));
      expect(adapter.requests.map((r) => r.method), ['GET']);
    });

    test('scrittura che dà 500: chiave e segreto non vanno nel log', () async {
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previousLevel);
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      adapter.handler = (options) => options.method == 'GET'
          ? FakeResponse(200, config())
          : const FakeResponse(500);

      await expectLater(api.setNotifyNewTitles(false),
          throwsA(isA<ServerErrorException>()));

      expect(adapter.requests.map((r) => r.method), ['GET', 'POST']);
      expect(records, isNotEmpty, reason: 'il 500 va nel log');
      final logged = [
        for (final record in records)
          '${record.message} ${record.error} ${record.stackTrace}',
      ].join('\n');
      expect(logged, isNot(contains('chiave')));
      expect(logged, isNot(contains('segreto')));
    });
  });
}
