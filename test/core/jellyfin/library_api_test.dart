import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
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

  test('previousEpisode: l\'episodio prima di quello indicato (spec H §8.1)',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['e3', 'e4', 'e5']));
    final previous = await api.previousEpisode('u1', 's1', 'e4');
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['adjacentTo'], 'e4');
    expect(last().query['isMissing'], false);
    expect(last().query['userId'], 'u1');
    expect(last().query, isNot(contains('seasonId')),
        reason: 'anche dalla stagione prima');
    expect(previous?.id, 'e3');

    adapter.handler = (_) => FakeResponse(200, itemsResult(['e1', 'e2']));
    expect(await api.previousEpisode('u1', 's1', 'e1'), isNull,
        reason: 'primo episodio');
  });

  test('allEpisodes: tutti gli episodi della serie, senza i mancanti',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['e1', 'e2']));
    final episodes = await api.allEpisodes('u1', 's1');
    expect(last().path, '/Shows/s1/Episodes');
    expect(last().query['isMissing'], false);
    expect(last().query['userId'], 'u1');
    expect(last().query, isNot(contains('seasonId')));
    expect(last().query['enableImageTypes'], 'Primary,Backdrop,Thumb,Logo');
    expect(episodes.map((e) => e.id), ['e1', 'e2']);
  });

  test('itemsByIds: gli elementi indicati, con le immagini delle card',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['m2', 'm1']));
    final items = await api.itemsByIds('u1', ['m1', 'm2']);
    expect(last().path, '/Items');
    expect(last().query['ids'], 'm1,m2');
    expect(last().query['userId'], 'u1');
    expect(last().query['enableImageTypes'], 'Primary,Backdrop,Thumb,Logo');
    // La sinossi serve al post-play del party: Jellyfin la manda solo se
    // richiesta.
    expect(last().query['fields'], contains('Overview'));
    expect(last().query['fields'], contains('PrimaryImageAspectRatio'));
    // Le serie del match mostrano le stagioni.
    expect(last().query['fields'], contains('ChildCount'));
    expect(items.map((item) => item.id), ['m2', 'm1']);
  });

  test('itemsByIds: con una lista vuota non parte nessuna richiesta',
      () async {
    // `ids=` vuoto farebbe rispondere a Jellyfin con le viste della libreria.
    expect(await api.itemsByIds('u1', const []), isEmpty);
    expect(adapter.requests, isEmpty);
  });

  group('itemsByIds a gruppi', () {
    /// Risponde con gli id chiesti; il primo gruppo arriva per ultimo.
    void echoIds() {
      adapter.handler = (options) async {
        final ids = (options.queryParameters['ids'] as String).split(',');
        if (ids.first == 'm0') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return FakeResponse(200, itemsResult(ids));
      };
    }

    List<String> askedIds(RequestOptions request) =>
        (request.queryParameters['ids'] as String).split(',');

    test('250 id: tre richieste da 100, 100 e 50, risultati in ordine',
        () async {
      echoIds();
      final ids = [for (var i = 0; i < 250; i++) 'm$i'];
      final items = await api.itemsByIds('u1', ids);
      expect(adapter.requests.map((r) => askedIds(r).length).toList()..sort(),
          [50, 100, 100]);
      expect(
          [for (final r in adapter.requests) askedIds(r).first],
          unorderedEquals(['m0', 'm100', 'm200']));
      for (final request in adapter.requests) {
        expect(request.path, '/Items');
        expect(request.queryParameters['userId'], 'u1');
        expect(request.queryParameters['fields'], contains('Overview'));
      }
      expect(items.map((item) => item.id), ids,
          reason: "concatenati nell'ordine dei gruppi, non di arrivo");
    });

    test('la richiesta più lunga resta sotto gli 8 KB di Kestrel e nginx',
        () async {
      echoIds();
      // Id di Jellyfin: 32 caratteri esadecimali, 35 byte con la virgola
      // codificata (%2C).
      final ids = [
        for (var i = 0; i < 1000; i++) i.toRadixString(16).padLeft(32, 'a'),
      ];
      await api.itemsByIds('u1', ids);
      expect(adapter.requests, hasLength(10));
      for (final request in adapter.requests) {
        expect(request.uri.toString().length, lessThan(4500));
      }
    });

    test('al massimo 100 id: una sola richiesta, come prima', () async {
      echoIds();
      final ids = [for (var i = 0; i < 100; i++) 'm$i'];
      final items = await api.itemsByIds('u1', ids);
      expect(adapter.requests, hasLength(1));
      expect(askedIds(adapter.requests.single), ids);
      expect(items.map((item) => item.id), ids);
    });

    test('101 id: due richieste, 100 e 1', () async {
      echoIds();
      final ids = [for (var i = 0; i < 101; i++) 'm$i'];
      final items = await api.itemsByIds('u1', ids);
      expect(adapter.requests.map((r) => askedIds(r).length).toList()..sort(),
          [1, 100]);
      expect(items.map((item) => item.id), ids);
    });

    test('un gruppo che fallisce fa fallire la lettura', () async {
      adapter.handler = (options) {
        final ids = (options.queryParameters['ids'] as String).split(',');
        return ids.contains('m150')
            ? const FakeResponse(500)
            : FakeResponse(200, itemsResult(ids));
      };
      await expectLater(
          api.itemsByIds('u1', [for (var i = 0; i < 250; i++) 'm$i']),
          throwsA(isA<ApiException>()));
    });
  });

  test('collectionItems: i titoli della saga in ordine di uscita (spec K §8.1)',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['m1', 'm2']));
    final items = await api.collectionItems('u1', 'c1');
    expect(last().path, '/Items');
    expect(last().query['userId'], 'u1');
    expect(last().query['parentId'], 'c1');
    expect(last().query['sortBy'], 'PremiereDate,ProductionYear,SortName');
    expect(last().query['sortOrder'], 'Ascending');
    // I titoli sono collegati alla collezione, non suoi discendenti.
    expect(last().query.containsKey('recursive'), isFalse);
    expect(last().query['enableImageTypes'], 'Primary,Backdrop,Thumb,Logo');
    expect(items.map((item) => item.id), ['m1', 'm2']);
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

  test('playHistory: film ed episodi visti, dal più recente, solo i dati di base',
      () async {
    await api.playHistory('u1', limit: 50);
    expect(last().path, '/Items');
    expect(last().query, {
      'userId': 'u1',
      'includeItemTypes': 'Movie,Episode',
      'isPlayed': true,
      'sortBy': 'DatePlayed',
      'sortOrder': 'Descending',
      'recursive': true,
      'limit': 50,
      'enableImages': false,
      'enableUserData': false,
    });
  });

  test('playedMovies: solo film visti, dal più recente, senza campi in più',
      () async {
    final movies = await api.playedMovies('u1', limit: 500);
    expect(movies.map((m) => m.id), ['a', 'b']);
    expect(last().query, {
      'userId': 'u1',
      'includeItemTypes': 'Movie',
      'isPlayed': true,
      'sortBy': 'DatePlayed',
      'sortOrder': 'Descending',
      'recursive': true,
      'limit': 500,
      'enableImages': false,
      'enableUserData': false,
      'fields': '',
    });
  });

  test('randomUnplayed: a caso, non visti, tipi, genere e i campi in più',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['a'], total: 632));
    final page = await api.randomUnplayed('u1',
        kinds: {ItemKind.series, ItemKind.movie}, genre: 'Commedia', limit: 50);
    expect(last().path, '/Items');
    expect(last().query['includeItemTypes'], 'Movie,Series');
    expect(last().query['sortBy'], 'Random');
    expect(last().query['isPlayed'], false);
    expect(last().query['recursive'], true);
    expect(last().query['limit'], 50);
    expect(last().query['genres'], 'Commedia');
    expect(last().query['userId'], 'u1');
    expect(
        last().query['fields'],
        'PrimaryImageAspectRatio,Genres,Overview,ChildCount,'
        'RecursiveItemCount');
    expect(page.items.single.id, 'a');
    expect(page.totalCount, 632);

    await api.randomUnplayed('u1', kinds: {ItemKind.movie}, limit: 50);
    expect(last().query.containsKey('genres'), isFalse);
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
