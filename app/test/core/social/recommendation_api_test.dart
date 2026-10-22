import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/social_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SocialApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SocialApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('amici a cui consigliare', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Friends': [
            {'UserId': 'u2', 'Name': 'Luigi', 'Online': true, 'CanSee': false},
          ],
        });
    final targets = await api.recommendationTargets('m1');
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/WonderFlixWatchParty/Recommendations/Targets');
    expect(request.queryParameters['itemId'], 'm1');
    expect(targets.single.name, 'Luigi');
    expect(targets.single.online, isTrue);
    expect(targets.single.canSee, isFalse);
  });

  test('consiglio: corpo e destinatari raggiunti', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Sent': 2});
    expect(await api.recommend('m1', ['u2', 'u3'], 'da vedere'), 2);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/WonderFlixWatchParty/Recommendations');
    expect(request.data, {
      'ItemId': 'm1',
      'To': ['u2', 'u3'],
      'Message': 'da vedere',
    });
  });

  test('consigli ricevuti, anche senza messaggio', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'ItemId': 'm1',
              'From': [
                {
                  'UserId': 'u2',
                  'Name': 'Luigi',
                  'Message': 'da vedere',
                  'CreatedAt': '2026-10-12T20:00:00Z',
                },
                {'UserId': 'u3', 'Name': 'Peach', 'CreatedAt': '2026-10-12T19:00:00Z'},
              ],
            },
          ],
        });
    final items = await api.recommendations();
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Recommendations');
    expect(items.single.itemId, 'm1');
    expect(items.single.from.map((s) => s.name), ['Luigi', 'Peach']);
    expect(items.single.from.first.message, 'da vedere');
    expect(items.single.from.last.message, isNull);
    expect(items.single.from.first.createdAt, DateTime.utc(2026, 10, 12, 20));
  });

  test('Non mi interessa', () async {
    await api.dismissRecommendation('m1');
    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/WonderFlixWatchParty/Recommendations/m1');
  });

  test('400 e 429', () async {
    adapter.handler = (_) => const FakeResponse(400);
    await expectLater(api.recommend('m1', ['u2'], null),
        throwsA(isA<SocialException>().having((e) => e.failure, 'failure', SocialFailure.forbidden)));
    adapter.handler = (_) => const FakeResponse(429);
    await expectLater(api.recommend('m1', ['u2'], null),
        throwsA(isA<SocialException>().having((e) => e.failure, 'failure', SocialFailure.rateLimited)));
  });
}
