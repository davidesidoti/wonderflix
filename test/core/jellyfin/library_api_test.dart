import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/library_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

Map<String, dynamic> itemsResult(List<String> ids, {int? total}) => {
      'Items': [
        for (final id in ids) {'Id': id, 'Name': 'N$id', 'Type': 'Movie'},
      ],
      'TotalRecordCount': total ?? ids.length,
    };

void main() {
  late FakeAdapter adapter;
  late LibraryApi api;

  setUp(() {
    adapter = FakeAdapter((_) => FakeResponse(200, itemsResult(['a', 'b'])));
    api = LibraryApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  RequestOptionsView last() => RequestOptionsView(adapter.requests.last);

  test('items usa ItemQuery e legge il totale', () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['a'], total: 250));
    final page = await api.items(const ItemQuery(kinds: {ItemKind.movie}),
        userId: 'u1', startIndex: 0, limit: 100);
    expect(last().path, '/Items');
    expect(last().query['includeItemTypes'], 'Movie');
    expect(page.items.single.id, 'a');
    expect(page.totalCount, 250);
  });

  test('resume e nextUp', () async {
    await api.resume('u1', limit: 10);
    expect(last().path, '/UserItems/Resume');
    expect(last().query['includeItemTypes'], 'Movie,Episode');
    expect(last().query['limit'], 10);

    await api.nextUp('u1', seriesId: 's1', limit: 1, enableResumable: true);
    expect(last().path, '/Shows/NextUp');
    expect(last().query['seriesId'], 's1');
    expect(last().query['enableResumable'], true);
  });

  test('item, stagioni, episodi, simili', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Id': 'm1', 'Name': 'Dune', 'Type': 'Movie'});
    final item = await api.item('u1', 'm1');
    expect(last().path, '/Items/m1');
    expect(last().query['userId'], 'u1');
    expect(item.name, 'Dune');

    adapter.handler = (_) => FakeResponse(200, itemsResult(['x']));
    await api.seasons('u1', 's1');
    expect(last().path, '/Shows/s1/Seasons');
    await api.episodes('u1', 's1', 'se1');
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['seasonId'], 'se1');
    await api.similar('u1', 'm1', limit: 12);
    expect(last().path, '/Items/m1/Similar');
  });

  test('filtri: generi e anni (dal più recente)', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Genres': ['Dramma', 'Azione'],
          'Years': [1999, 2024, 2010],
        });
    final filters = await api.filters('u1', ItemKind.series);
    expect(last().path, '/Items/Filters');
    expect(last().query['includeItemTypes'], 'Series');
    expect(filters.genres, ['Dramma', 'Azione']);
    expect(filters.years, [2024, 2010, 1999]);
  });

  test('ricerca persone', () async {
    await api.searchPeople('u1', 'zen', limit: 12);
    expect(last().path, '/Persons');
    expect(last().query['searchTerm'], 'zen');
  });

  test('preferiti e visti: POST per attivare, DELETE per disattivare', () async {
    adapter.handler = (_) => const FakeResponse(200, {'IsFavorite': true, 'Played': true});
    final fav = await api.setFavorite('u1', 'm1', favorite: true);
    expect(last().method, 'POST');
    expect(last().path, '/UserFavoriteItems/m1');
    expect(fav.isFavorite, isTrue);

    await api.setFavorite('u1', 'm1', favorite: false);
    expect(last().method, 'DELETE');

    await api.setPlayed('u1', 'm1', played: true);
    expect(last().method, 'POST');
    expect(last().path, '/UserPlayedItems/m1');
    await api.setPlayed('u1', 'm1', played: false);
    expect(last().method, 'DELETE');
  });

  test('nextEpisode: l\'episodio dopo quello indicato', () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['e4', 'e5']));
    final next = await api.nextEpisode('u1', 's1', 'e4');
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['startItemId'], 'e4');
    expect(last().query['limit'], 2);
    expect(last().query['isMissing'], false);
    expect(last().query['userId'], 'u1');
    expect(next?.id, 'e5');

    adapter.handler = (_) => FakeResponse(200, itemsResult(['e9']));
    expect(await api.nextEpisode('u1', 's1', 'e9'), isNull,
        reason: 'ultimo episodio');
  });

  test('episodesFrom: l\'episodio indicato e i successivi', () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['e4', 'e5', 'e6']));
    final episodes = await api.episodesFrom('u1', 's1', 'e4', limit: 50);
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['startItemId'], 'e4');
    expect(last().query['limit'], 50);
    expect(last().query['isMissing'], false);
    expect(last().query['userId'], 'u1');
    // Per la coda servono solo gli id: niente immagini, dati utente e campi
    // in più.
    expect(last().query['enableImages'], false);
    expect(last().query['enableUserData'], false);
    expect(last().query, isNot(contains('fields')));
    expect(last().query, isNot(contains('enableImageTypes')));
    expect(episodes.map((e) => e.id), ['e4', 'e5', 'e6']);
  });

  test('localTrailers: array di elementi', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {'Id': 't1', 'Name': 'Trailer', 'Type': 'Trailer'},
        ]);
    final trailers = await api.localTrailers('u1', 'm1');
    expect(last().path, '/Items/m1/LocalTrailers');
    expect(last().query['userId'], 'u1');
    expect(trailers.single.id, 't1');
  });

  test('nextUp con limite di data', () async {
    await api.nextUp('u1',
        limit: 20, dateCutoff: DateTime.utc(2025, 9, 29, 10, 30));
    expect(last().query['nextUpDateCutoff'], '2025-09-29T10:30:00.000Z');

    await api.nextUp('u1', limit: 20);
    expect(last().query.containsKey('nextUpDateCutoff'), isFalse);
  });
}

/// Accesso comodo a metodo, percorso e query di una richiesta registrata.
class RequestOptionsView {
  RequestOptionsView(this._options);

  final RequestOptions _options;

  String get method => _options.method;
  String get path => _options.path;
  Map<String, dynamic> get query => _options.queryParameters;
}
