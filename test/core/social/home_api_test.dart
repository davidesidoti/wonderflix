import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/home_api.dart';
import 'package:wonderflix/core/social/home_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late HomeApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, <String, dynamic>{}));
    api = HomeApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('Home dell\'admin: Rows assente o null vuol dire mai impostata',
      () async {
    expect(await api.layout(), isNull);
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Home/Layout');

    adapter.handler = (_) => const FakeResponse(200, {'Rows': null});
    expect(await api.layout(), isNull);

    adapter.handler = (_) => const FakeResponse(200, {'Rows': <String>[]});
    expect(await api.layout(), isEmpty);

    adapter.handler =
        (_) => const FakeResponse(200, {'Rows': ['resume', 'myList']});
    expect(await api.layout(), ['resume', 'myList']);
  });

  test('salvare la Home dell\'admin manda le righe, anche null', () async {
    adapter.handler = (options) => FakeResponse(200, options.data);
    expect(await api.setLayout(['myList', 'resume']), ['myList', 'resume']);
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.data, {
      'Rows': ['myList', 'resume'],
    });

    expect(await api.setLayout(null), isNull);
    expect(adapter.requests.last.data, {'Rows': null});
  });

  test('serie in arrivo: voci, blocchi e voci incomplete scartate', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'SeriesName': 'American Hostage',
              'SeasonNumber': 1,
              'EpisodeNumber': 5,
              'EpisodeTitle': 'Episode 5',
              'AirDateUtc': '2026-10-12T01:00:00+00:00',
              'TvdbId': 462907,
              'TmdbId': 239618,
              'PosterUrl': 'https://artworks.thetvdb.com/p.jpg',
              'BackdropUrl': 'https://artworks.thetvdb.com/f.jpg',
              'JellyfinSeriesId': 'abc123',
            },
            {
              'SeriesName': 'Crystal Lake',
              'SeasonNumber': 1,
              'EpisodeNumber': 1,
              'LastEpisodeNumber': 8,
              'AirDateUtc': '2026-10-15T09:00:00+00:00',
              'PosterUrl': '/sonarr/MediaCover/1/poster.jpg',
            },
            {'SeriesName': 'Senza data', 'SeasonNumber': 1, 'EpisodeNumber': 1},
            {'AirDateUtc': '2026-10-15T09:00:00+00:00'},
            'non un oggetto',
          ],
        });

    final page = await api.upcomingSeries();

    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Upcoming/Series');
    expect(page.error, isNull);
    expect(page.items, hasLength(2));
    final hostage = page.items.first;
    expect(hostage.seriesName, 'American Hostage');
    expect(hostage.seasonNumber, 1);
    expect(hostage.episodeNumber, 5);
    expect(hostage.lastEpisodeNumber, isNull);
    expect(hostage.episodeTitle, 'Episode 5');
    expect(hostage.airDate, DateTime.utc(2026, 10, 12, 1));
    expect(hostage.tvdbId, 462907);
    expect(hostage.tmdbId, 239618);
    expect(hostage.posterUrl, 'https://artworks.thetvdb.com/p.jpg');
    expect(hostage.backdropUrl, 'https://artworks.thetvdb.com/f.jpg');
    expect(hostage.jellyfinSeriesId, 'abc123');
    final lake = page.items.last;
    expect(lake.lastEpisodeNumber, 8);
    expect(lake.tmdbId, isNull);
    expect(lake.posterUrl, isNull, reason: 'solo indirizzi http(s) completi');
  });

  test('film in arrivo e codici d\'errore', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'Title': 'Hope',
              'Year': 2026,
              'TmdbId': 1058424,
              'DigitalRelease': '2026-10-13T00:00:00+00:00',
              'PosterUrl': 'https://image.tmdb.org/t/p/original/p.jpg',
            },
            {'Title': 'Senza TMDB', 'DigitalRelease': '2026-10-13T00:00:00+00:00'},
          ],
        });
    final page = await api.upcomingMovies();
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Upcoming/Movies');
    final hope = page.items.single;
    expect(hope.title, 'Hope');
    expect(hope.year, 2026);
    expect(hope.tmdbId, 1058424);
    expect(hope.digitalRelease, DateTime.utc(2026, 10, 13));
    expect(hope.posterUrl, 'https://image.tmdb.org/t/p/original/p.jpg');
    expect(hope.backdropUrl, isNull);

    for (final (wire, error) in [
      ('NotConfigured', UpcomingError.notConfigured),
      ('Unauthorized', UpcomingError.unauthorized),
      ('Unreachable', UpcomingError.unreachable),
      ('Sconosciuto', UpcomingError.unreachable),
    ]) {
      adapter.handler =
          (_) => FakeResponse(200, {'Items': <Object>[], 'Error': wire});
      final failed = await api.upcomingMovies();
      expect(failed.error, error, reason: wire);
      expect(failed.items, isEmpty);
    }
  });

  test('risposte inattese', () async {
    adapter.handler = (_) => const FakeResponse(200, ['non un oggetto']);
    await expectLater(api.upcomingSeries(), throwsA(isA<ServerErrorException>()));
    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(api.layout(), throwsA(isA<NotFoundException>()));
  });
}
