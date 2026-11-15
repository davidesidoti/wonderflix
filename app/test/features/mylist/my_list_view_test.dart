import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/catalog/catalog_genres.dart';
import 'package:wonderflix/features/mylist/my_list_view.dart';

/// Preferito col cuore.
JellyfinItem fav(
  String id, {
  String? name,
  String? sortName,
  ItemKind kind = ItemKind.movie,
  int? year,
  double? rating,
  DateTime? created,
  List<String> genres = const [],
  bool played = false,
  int position = 0,
  int? unplayed,
  int? recursive,
  double? percentage,
  String? status,
}) =>
    JellyfinItem(
      id: id,
      name: name ?? id,
      kind: kind,
      sortName: sortName,
      productionYear: year,
      communityRating: rating,
      dateCreated: created,
      genres: genres,
      status: status,
      recursiveItemCount: recursive,
      userData: UserItemData(
        isFavorite: true,
        played: played,
        playbackPositionTicks: position,
        unplayedItemCount: unplayed,
        playedPercentage: percentage,
      ),
    );

List<String> ids(List<JellyfinItem> items) => [for (final i in items) i.id];

/// 25 titoli da iniziare, senza data né generi e dopo gli altri per nome: con loro la lista supera la
/// soglia, e genere e ricerca filtrano.
final filler = [for (var i = 0; i < 25; i++) fav('z$i', name: 'Zeta $i')];

/// Tutti da iniziare: il primo è il titolo di punta, poi la lista.
List<String> order(MyListView v) => ids([?v.hero, ...v.start]);

MyListView view(
  List<JellyfinItem> items, {
  MyListTab tab = MyListTab.all,
  MyListFilters filters = const MyListFilters(),
  Map<String, UserItemData> overrides = const {},
  Map<String, DateTime> added = const {},
}) =>
    buildMyListView(items, tab, filters, overrides, added);

MyListFilters sortedBy(CatalogSort sort, {bool reversed = false}) =>
    MyListFilters(sort: sort, reversed: reversed);

void main() {
  test('scheda dall\'indirizzo: sconosciuta o assente è all', () {
    expect(MyListTab.parse('movies'), MyListTab.movies);
    expect(MyListTab.parse('series'), MyListTab.series);
    expect(MyListTab.parse('boh'), MyListTab.all);
    expect(MyListTab.parse(null), MyListTab.all);
  });

  test('filtri: hasRefinements e copyWith', () {
    const f = MyListFilters();
    expect(f.hasRefinements, isFalse);
    expect(f.copyWith(genre: 'Dramma').hasRefinements, isTrue);
    expect(f.copyWith(search: 'x').hasRefinements, isTrue);
    final g = f.copyWith(genre: 'Dramma');
    expect(g.copyWith(search: 'x').genre, 'Dramma');
    expect(g.copyWith(genre: null).genre, isNull);
  });

  group('gruppi', () {
    final fPlayed = fav('fp', played: true);
    final fStarted = fav('fs', position: 10);
    final fNew = fav('fn');
    final sDone = fav('sd', kind: ItemKind.series, unplayed: 0);
    final sStarted =
        fav('ss', kind: ItemKind.series, unplayed: 3, percentage: 40);
    final sNew = fav('sn',
        kind: ItemKind.series, unplayed: 8, recursive: 8, percentage: 0);
    final sNoCounts = fav('sx', kind: ItemKind.series);

    test('film: visto, iniziato, nuovo', () {
      expect(
          [for (final i in [fPlayed, fStarted, fNew]) myListGroup(i, i.userData)],
          [MyListGroup.watched, MyListGroup.resume, MyListGroup.start]);
    });

    test('serie: vista tutta, iniziata, mai iniziata, senza conteggi', () {
      expect(
          [
            for (final i in [sDone, sStarted, sNew, sNoCounts])
              myListGroup(i, i.userData)
          ],
          [
            MyListGroup.watched,
            MyListGroup.resume,
            MyListGroup.start,
            MyListGroup.start
          ]);
    });

    test('serie iniziata senza playedPercentage: decide recursiveItemCount', () {
      final s = fav('s', kind: ItemKind.series, unplayed: 3, recursive: 8);
      expect(myListGroup(s, s.userData), MyListGroup.resume);
    });

    test('serie con playedPercentage 0: da iniziare, conteggi a parte', () {
      final s = fav('s',
          kind: ItemKind.series, unplayed: 3, recursive: 8, percentage: 0);
      expect(myListGroup(s, s.userData), MyListGroup.start);
    });

    test('dati della sessione al posto di quelli caricati', () {
      final r = view([fNew], overrides: {
        'fn': const UserItemData(isFavorite: true, played: true)
      });
      expect(r.watchedCount, 1);
      expect(r.startCount, 0);
    });
  });

  group('titolo di punta', () {
    final items = [
      fav('vs', name: 'A', created: DateTime.utc(2024)),
      fav('vq', name: 'B', position: 5, created: DateTime.utc(2023)),
      fav('vr', name: 'C', position: 5, created: DateTime.utc(2022)),
      fav('vw', name: 'D', played: true),
    ];

    test(
        'il primo da continuare nell\'ordine, fuori dalle liste, dentro i conteggi',
        () {
      final v = view(items);
      expect(v.hero!.id, 'vq');
      expect(ids(v.resume), ['vr']);
      expect(v.resumeCount, 2);
      expect(v.startCount, 1);
      expect(v.watchedCount, 1);
      expect(v.tabCount, 4);
    });

    test('senza da continuare: il primo da iniziare', () {
      final v = view([fav('b', name: 'B'), fav('a', name: 'A')],
          filters: sortedBy(CatalogSort.title));
      expect(v.hero!.id, 'a');
      expect(ids(v.start), ['b']);
      expect(v.startCount, 2);
    });

    test('solo visti: nessuno', () {
      final v = view([fav('w', played: true)]);
      expect(v.hero, isNull);
      expect(ids(v.watched), ['w']);
    });

    test('genere e ricerca non lo cambiano', () {
      final v = view([
        fav('x',
            name: 'Alpha',
            position: 5,
            genres: ['Dramma'],
            created: DateTime.utc(2024)),
        fav('y',
            name: 'Beta',
            position: 5,
            genres: ['Horror'],
            created: DateTime.utc(2023)),
        ...filler,
      ], filters: const MyListFilters(genre: 'Horror', search: 'bet'));
      expect(v.hero!.id, 'x');
      expect(ids(v.resume), ['y']);
    });
  });

  group('ordine', () {
    List<JellyfinItem> dated() => [
          fav('senzaVecchio', created: DateTime.utc(2020)),
          fav('conData1'),
          fav('senzaRecente', created: DateTime.utc(2024)),
          fav('conData2'),
        ];
    final added = {
      'condata1': DateTime.utc(2021),
      'condata2': DateTime.utc(2022),
    };

    test('aggiunti: prima le date salvate, poi dateCreated', () {
      expect(order(view(dated(), added: added)),
          ['conData2', 'conData1', 'senzaRecente', 'senzaVecchio']);
    });

    test('le date si cercano con jellyfinIdKey', () {
      final v = view([fav('AA-BB'), fav('cc')],
          added: {'aabb': DateTime.utc(2000), 'cc': DateTime.utc(2001)});
      expect(order(v), ['cc', 'AA-BB']);
    });

    test('aggiunti al contrario: tutto rovesciato', () {
      final v = view(dated(),
          filters: sortedBy(CatalogSort.dateAdded, reversed: true),
          added: added);
      expect(order(v),
          ['senzaVecchio', 'senzaRecente', 'conData1', 'conData2']);
    });

    test('titolo A→Z, al contrario Z→A; a parità per titolo', () {
      final items = [
        fav('a', name: 'The Matrix', sortName: 'matrix'),
        fav('b', name: 'alien'),
        fav('c', name: 'Blade Runner'),
      ];
      expect(order(view(items, filters: sortedBy(CatalogSort.title))),
          ['b', 'c', 'a']);
      expect(
          order(view(items,
                  filters: sortedBy(CatalogSort.title, reversed: true))),
          ['a', 'c', 'b']);
      final same = [fav('2', name: 'Heat'), fav('1', name: 'Heat')];
      expect(
          order(view(same, filters: sortedBy(CatalogSort.title, reversed: true))),
          ['1', '2']);
    });

    test('anno: dal più recente, a parità per titolo, senza anno in fondo', () {
      final items = [
        fav('z', name: 'Zodiac', year: 2007),
        fav('n', name: 'Nessuno'),
        fav('a', name: 'Alien', year: 2007),
        fav('d', name: 'Dune', year: 2021),
      ];
      expect(order(view(items, filters: sortedBy(CatalogSort.year))),
          ['d', 'a', 'z', 'n']);
      // Al contrario: il più vecchio prima, chi non ha l'anno resta in fondo
      // e a parità vale sempre il titolo A→Z.
      expect(
          order(view(items, filters: sortedBy(CatalogSort.year, reversed: true))),
          ['a', 'z', 'd', 'n']);
    });

    test('voto: dal più alto, senza voto in fondo per titolo', () {
      final items = [
        fav('b', name: 'B', rating: 7.1),
        fav('y', name: 'Y'),
        fav('x', name: 'X'),
        fav('a', name: 'A', rating: 8.4),
      ];
      expect(order(view(items, filters: sortedBy(CatalogSort.rating))),
          ['a', 'b', 'x', 'y']);
      expect(
          order(view(items,
                  filters: sortedBy(CatalogSort.rating, reversed: true))),
          ['b', 'a', 'x', 'y']);
    });
  });

  test('schede: film, serie, tutti; conteggi della scheda', () {
    final items = [
      fav('m1'),
      fav('m2', position: 1),
      fav('s1', kind: ItemKind.series, unplayed: 2),
    ];
    final movies = view(items, tab: MyListTab.movies);
    expect(movies.tabCount, 2);
    expect(movies.resumeCount, 1);
    expect(movies.startCount, 1);
    final series = view(items, tab: MyListTab.series);
    expect(series.tabCount, 1);
    expect(series.hero!.id, 's1');
    expect(view(items).tabCount, 3);
  });

  test('generi uniti con genreLabel, per conteggio poi nome', () {
    final v = view([
      fav('a', genres: ['Drama', 'Horror']),
      fav('b', genres: ['Dramma']),
      fav('c', genres: ['Dramma', 'Drama']),
      fav('d', genres: ['Azione']),
    ]);
    expect(v.genres, [
      const GenreCount('Dramma', 3),
      const GenreCount('Azione', 1),
      const GenreCount('Horror', 1),
    ]);
  });

  test('genere: confronto su genreLabel', () {
    final v = view([
      fav('a', genres: ['Drama']),
      fav('b', genres: ['Dramma']),
      fav('c', genres: ['Horror']),
      ...filler,
    ], filters: const MyListFilters(genre: 'Dramma'));
    expect([...ids([?v.hero]), ...ids(v.start)], unorderedEquals(['a', 'b']));
    expect(v.tabCount, 28);
  });

  test('ricerca sul nome senza maiuscole', () {
    final v = view([
      fav('d', name: 'Dune'),
      fav('h', name: 'Heat'),
      fav('p', name: 'Dune: Parte Due'),
      ...filler,
    ], filters: const MyListFilters(search: '  DUNE '));
    expect([...ids([?v.hero]), ...ids(v.start)], unorderedEquals(['d', 'p']));
  });

  test(
      'noResults: filtro che lascia solo il titolo di punta → false; nessuno → true',
      () {
    final items = [
      fav('a', name: 'Alpha', position: 5, created: DateTime.utc(2024)),
      fav('b', name: 'Beta', created: DateTime.utc(2023)),
      ...filler,
    ];
    final onlyHero = view(items, filters: const MyListFilters(search: 'alpha'));
    expect(onlyHero.hero!.id, 'a');
    expect(onlyHero.resume, isEmpty);
    expect(onlyHero.noResults, isFalse);
    expect(view(items, filters: const MyListFilters(search: 'zzz')).noResults,
        isTrue);
    expect(view(items).noResults, isFalse);
  });

  // Senza la riga dei generi e il campo di ricerca un filtro rimasto acceso
  // nasconderebbe titoli senza modo di toglierlo.
  test('fino a 24 preferiti genere e ricerca non filtrano', () {
    final items = [
      fav('a', genres: ['Dramma'], created: DateTime.utc(2024)),
      fav('b', genres: ['Horror'], created: DateTime.utc(2023)),
      fav('c', genres: ['Dramma'], created: DateTime.utc(2022)),
    ];
    expect(
      order(view(items, filters: const MyListFilters(genre: 'Horror'))),
      ['a', 'b', 'c'],
    );
    final search = view(items, filters: const MyListFilters(search: 'zzz'));
    expect(order(search), ['a', 'b', 'c']);
    expect(search.noResults, isFalse);
  });

  test('soglia: 24 preferiti no, 25 sì (tutte le schede)', () {
    List<JellyfinItem> n(int count) => [
          for (var i = 0; i < count; i++)
            fav('m$i', kind: i.isEven ? ItemKind.movie : ItemKind.series)
        ];
    expect(view(n(24)).showRefinements, isFalse);
    expect(view(n(25)).showRefinements, isTrue);
    // Conta tutte le schede, non solo quella aperta.
    expect(view(n(25), tab: MyListTab.series).showRefinements, isTrue);
  });

  test('removableWatched lascia le serie in corso viste tutte', () {
    final v = view([
      fav('f', played: true),
      fav('ended', kind: ItemKind.series, unplayed: 0, status: 'Ended'),
      fav('going', kind: ItemKind.series, unplayed: 0, status: 'Continuing'),
    ]);
    expect(v.watched, hasLength(3));
    expect(ids(v.removableWatched).toSet(), {'f', 'ended'});
  });

  test('tolto in questa sessione: sparisce; nessuno rimasto: listEmpty', () {
    final v = view([fav('d'), fav('e')],
        overrides: {'d': const UserItemData(isFavorite: false)});
    expect(v.tabCount, 1);
    expect(v.listEmpty, isFalse);
    final none = view([fav('d')], overrides: {'d': const UserItemData()});
    expect(none.listEmpty, isTrue);
    expect(none.hero, isNull);
  });
}
