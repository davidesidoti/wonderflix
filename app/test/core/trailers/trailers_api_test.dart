import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/trailers/trailers_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late JellyfinHttp http;
  late TrailersApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {'Available': true}));
    http = JellyfinHttp(
      baseUrl: testServerUrl,
      clientInfo: testClientInfo,
      adapter: adapter,
    );
    api = TrailersApi(http);
  });

  test('available manda itemId', () async {
    expect(await api.available(const LibraryTrailer('abc')), isTrue);
    expect(adapter.requests.last.path, '/WonderFlixWatchParty/Trailers/Info');
    expect(adapter.requests.last.queryParameters, {'itemId': 'abc'});
  });

  test('available manda tmdbId e tipo', () async {
    await api.available(const TmdbTrailer('tv', 7));
    expect(adapter.requests.last.queryParameters, {'tmdbId': 7, 'type': 'tv'});
  });

  test('available è false su 404 e su errore', () async {
    adapter.handler = (_) => const FakeResponse(404);
    expect(await api.available(const LibraryTrailer('abc')), isFalse);
    adapter.handler = (_) => const FakeResponse(500);
    expect(await api.available(const LibraryTrailer('abc')), isFalse);
  });

  test('start manda il soggetto e legge lo stato', () async {
    adapter.handler = (_) =>
        const FakeResponse(200, {'Key': '25WcssMq1VM', 'State': 'Downloading'});
    final status = await api.start(const TmdbTrailer('movie', 7));
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.path, '/WonderFlixWatchParty/Trailers/Start');
    expect(adapter.requests.last.data, {'Type': 'movie', 'TmdbId': 7});
    expect(status.key, '25WcssMq1VM');
    expect(status.state, TrailerState.downloading);

    await api.start(const LibraryTrailer('abc'));
    expect(adapter.requests.last.data, {'ItemId': 'abc'});
  });

  test('uno stato sconosciuto è failed', () async {
    adapter.handler = (_) =>
        const FakeResponse(200, {'Key': 'k', 'State': 'Boh'});
    expect((await api.status('k')).state, TrailerState.failed);
    expect(adapter.requests.last.queryParameters, {'key': 'k'});
  });

  test('start e status lanciano su 404 e su errore', () async {
    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(
      api.start(const LibraryTrailer('abc')),
      throwsA(isA<TrailerUnavailableException>()),
    );
    adapter.handler = (_) => const FakeResponse(500);
    await expectLater(
      api.status('k'),
      throwsA(isA<TrailerUnavailableException>()),
    );
  });

  test('streamUrl porta la chiave API', () {
    http.setCredentials(token: 'tok-1', deviceId: null);
    expect(
      api.streamUrl('25WcssMq1VM'),
      'https://media.example.com/WonderFlixWatchParty/Trailers/25WcssMq1VM/Stream?ApiKey=tok-1',
    );
  });
}
