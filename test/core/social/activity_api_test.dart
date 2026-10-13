import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';

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

  test('amico che guarda un episodio, e uno senza NowPlaying', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Friends': [
            {
              'UserId': 'u2',
              'Name': 'Luigi',
              'Online': true,
              'Party': null,
              'NowPlaying': {
                'ItemId': 'e1',
                'Title': 'Pilot',
                'SeriesId': 's1',
                'SeriesName': 'The Bear',
                'Season': 2,
                'Episode': 3,
              },
            },
            {'UserId': 'u3', 'Name': 'Peach', 'Online': true, 'Party': null},
          ],
          'Incoming': [],
          'Outgoing': [],
        });
    final friends = (await api.friends()).friends;
    final playing = friends.first.nowPlaying!;
    expect(playing.itemId, 'e1');
    expect(playing.title, 'Pilot');
    expect(playing.seriesId, 's1');
    expect(playing.seriesName, 'The Bear');
    expect(playing.season, 2);
    expect(playing.episode, 3);
    expect(friends.last.nowPlaying, isNull);
  });

  test('film: niente serie, stagione o numero', () {
    final entry = FriendEntry.fromJson(const {
      'UserId': 'u2',
      'Name': 'Luigi',
      'Online': true,
      'NowPlaying': {'ItemId': 'm1', 'Title': 'Dune'},
    });
    expect(entry.nowPlaying!.title, 'Dune');
    expect(entry.nowPlaying!.seriesName, isNull);
    expect(entry.nowPlaying!.season, isNull);
  });

  test('posizione dell\'amico: i tick diventano una durata', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'ItemId': 'm1',
          'PositionTicks': 25200000000,
        });
    final position = await api.friendNowPlaying('u2');
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/WonderFlixWatchParty/Friends/u2/NowPlaying');
    expect(position.itemId, 'm1');
    expect(position.position, const Duration(minutes: 42));
  });

  test('posizione: 409 = conflict', () async {
    adapter.handler = (_) => const FakeResponse(409);
    await expectLater(
        api.friendNowPlaying('u2'),
        throwsA(isA<SocialException>()
            .having((e) => e.failure, 'failure', SocialFailure.conflict)));
  });

  test('impostazione: lettura e scrittura', () async {
    adapter.handler = (_) => const FakeResponse(200, {'ShareActivity': false});
    expect(await api.activitySettings(), isFalse);
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Activity/Settings');

    adapter.handler = (_) => const FakeResponse(204);
    await api.setActivitySettings(true);
    final request = adapter.requests.last;
    expect(request.method, 'PUT');
    expect(request.path, '/WonderFlixWatchParty/Activity/Settings');
    expect(request.data, {'ShareActivity': true});
  });

  test('Visti dagli amici', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'ItemId': 'm1',
              'By': [
                {'UserId': 'u2', 'Name': 'Luigi', 'WatchedAt': '2026-10-13T20:00:00Z'},
                {'UserId': 'u3', 'Name': 'Peach', 'WatchedAt': '2026-10-12T19:00:00Z'},
              ],
            },
          ],
        });
    final items = await api.friendsWatched();
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Activity/FriendsWatched');
    expect(items.single.itemId, 'm1');
    expect(items.single.by.map((w) => w.name), ['Luigi', 'Peach']);
    expect(items.single.by.first.watchedAt, DateTime.utc(2026, 10, 13, 20));
  });
}
