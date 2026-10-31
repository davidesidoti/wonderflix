import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/notifications_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  const base = '/WonderFlixWatchParty/Notifications';
  late FakeAdapter adapter;
  late NotificationsApi api;

  setUp(() {
    adapter = FakeAdapter((options) => switch ((options.method, options.path)) {
          ('GET', base) => const FakeResponse(200, {
              'VapidPublicKey': 'BKey',
              'Types': [
                {'Type': 'Invite', 'Enabled': true},
                {'Type': 'DiskAlmostFull', 'Enabled': false},
              ],
            }),
          _ => const FakeResponse(204),
        });
    api = NotificationsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('get legge la chiave VAPID e i tipi nell\'ordine', () async {
    final info = await api.get();
    expect(info.vapidPublicKey, 'BKey');
    expect([for (final t in info.types) (t.type, t.enabled)],
        [('Invite', true), ('DiskAlmostFull', false)]);
  });

  test('get con una risposta incompleta è un errore del server', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Types': []});
    await expectLater(api.get(), throwsA(isA<ServerErrorException>()));
    adapter.handler = (_) => const FakeResponse(200, {
          'VapidPublicKey': 'BKey',
          'Types': [
            {'Type': 'Invite'}
          ],
        });
    await expectLater(api.get(), throwsA(isA<ServerErrorException>()));
  });

  test('setEnabled fa PUT sul tipo', () async {
    await api.setEnabled('DiskAlmostFull', false);
    final request = adapter.requests.single;
    expect((request.method, request.path), ('PUT', '$base/Types/DiskAlmostFull'));
    expect(request.data, {'Enabled': false});
  });

  test('subscribe manda i quattro campi', () async {
    await api.subscribe(
        endpoint: 'https://push.example/abc',
        p256dh: 'pk',
        auth: 'au',
        language: 'it');
    final request = adapter.requests.single;
    expect((request.method, request.path), ('POST', '$base/Subscriptions'));
    expect(request.data, {
      'Endpoint': 'https://push.example/abc',
      'P256dh': 'pk',
      'Auth': 'au',
      'Language': 'it',
    });
  });

  test('unsubscribe fa DELETE con l\'endpoint nel corpo', () async {
    await api.unsubscribe('https://push.example/abc');
    final request = adapter.requests.single;
    expect((request.method, request.path), ('DELETE', '$base/Subscriptions'));
    expect(request.data, {'Endpoint': 'https://push.example/abc'});
  });

  test('un 400 è un errore', () async {
    adapter.handler = (_) => const FakeResponse(400);
    await expectLater(
        api.setEnabled('Boh', true), throwsA(isA<ApiException>()));
  });
}
