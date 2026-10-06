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
