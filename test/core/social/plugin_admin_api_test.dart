import 'package:flutter_test/flutter_test.dart';
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
}
