import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/mylist/my_list_view.dart';

/// Preferito col cuore.
JellyfinItem fav(
  String id, {
  String? name,
  String? sortName,
  int? year,
  double? rating,
  DateTime? added,
  List<String> genres = const [],
  bool played = false,
}) =>
    JellyfinItem(
      id: id,
      name: name ?? id,
      kind: ItemKind.movie,
      sortName: sortName,
      productionYear: year,
      communityRating: rating,
      dateCreated: added,
      genres: genres,
      userData: UserItemData(isFavorite: true, played: played),
    );

List<String> ids(MyListView view) => [for (final item in view.items) item.id];

MyListView view(
  List<JellyfinItem> items, [
  ItemQuery filters = myListInitialFilters,
  Map<String, UserItemData> overrides = const {},
]) =>
    buildMyListView(items, filters, overrides);

ItemQuery sortedBy(CatalogSort sort) => myListInitialFilters.copyWith(sort: sort);

void main() {
  test('filtri iniziali: film e serie dalla data di aggiunta, senza filtri', () {
    expect(myListInitialFilters.kinds, {ItemKind.movie, ItemKind.series});
    expect(myListInitialFilters.sort, CatalogSort.dateAdded);
    expect(myListInitialFilters.hasFilters, isFalse);
  });

  group('ordine', () {
    test('titolo: per SortName senza maiuscole, il nome se manca', () {
      final result = view([
        fav('a', name: 'The Matrix', sortName: 'matrix'),
        fav('b', name: 'alien'),
        fav('c', name: 'Blade Runner', sortName: 'Blade Runner'),
      ], sortedBy(CatalogSort.title));
      expect(ids(result), ['b', 'c', 'a']);
    });

    test('titoli uguali: per id, sempre nello stesso ordine', () {
      final result = view([fav('2', name: 'Heat'), fav('1', name: 'Heat')],
          sortedBy(CatalogSort.title));
      expect(ids(result), ['1', '2']);
    });

    test('data di aggiunta: dalla più recente, senza data in fondo', () {
      final result = view([
        fav('old', added: DateTime.utc(2020)),
        fav('none'),
        fav('new', added: DateTime.utc(2024)),
      ], sortedBy(CatalogSort.dateAdded));
      expect(ids(result), ['new', 'old', 'none']);
    });

    test('anno: dal più recente, a parità per titolo, senza anno in fondo', () {
      final result = view([
        fav('z', name: 'Zodiac', year: 2007),
        fav('n', name: 'Nessuno'),
        fav('a', name: 'Alien', year: 2007),
        fav('d', name: 'Dune', year: 2021),
      ], sortedBy(CatalogSort.year));
      expect(ids(result), ['d', 'a', 'z', 'n']);
    });

    test('voto: dal più alto, senza voto in fondo per titolo', () {
      final result = view([
        fav('b', name: 'B', rating: 7.1),
        fav('y', name: 'Y'),
        fav('x', name: 'X'),
        fav('a', name: 'A', rating: 8.4),
      ], sortedBy(CatalogSort.rating));
      expect(ids(result), ['a', 'b', 'x', 'y']);
    });
  });

  group('filtri', () {
    final items = [
      fav('d', name: 'Dune', year: 2021, genres: ['Fantascienza', 'Avventura'],
          played: true),
      fav('h', name: 'Heat', year: 1995, genres: ['Crimine']),
      fav('a', name: 'Arrival', year: 2016, genres: ['Fantascienza']),
    ];
    final byTitle = sortedBy(CatalogSort.title);

    test('genere', () {
      expect(ids(view(items, byTitle.copyWith(genres: {'Fantascienza'}))),
          ['a', 'd']);
    });

    test('anno', () {
      expect(ids(view(items, byTitle.copyWith(year: 1995))), ['h']);
    });

    test('visti e non visti', () {
      expect(ids(view(items, byTitle.copyWith(watched: WatchedFilter.watched))),
          ['d']);
      expect(
          ids(view(items, byTitle.copyWith(watched: WatchedFilter.unwatched))),
          ['a', 'h']);
    });

    test('più filtri insieme', () {
      expect(
          ids(view(
              items,
              byTitle.copyWith(
                  genres: {'Fantascienza'}, watched: WatchedFilter.unwatched))),
          ['a']);
    });

    test('visto segnato in questa sessione', () {
      final result = view(
          items,
          byTitle.copyWith(watched: WatchedFilter.watched),
          {'h': const UserItemData(isFavorite: true, played: true)});
      expect(ids(result), ['d', 'h']);
    });
  });

  group('cuore', () {
    test('tolto in questa sessione: sparisce, la lista resta vuota', () {
      final result = view([fav('d', name: 'Dune')], myListInitialFilters,
          {'d': const UserItemData()});
      expect(result.items, isEmpty);
      expect(result.listEmpty, isTrue);
    });

    test('titoli presenti ma nessun risultato: la lista non è vuota', () {
      final result = view([fav('d', name: 'Dune', year: 2021)],
          myListInitialFilters.copyWith(year: 1990));
      expect(result.items, isEmpty);
      expect(result.listEmpty, isFalse);
    });
  });

  group('opzioni', () {
    test('generi senza doppioni in ordine alfabetico, anni dal più recente', () {
      final result = view([
        fav('d', year: 2021, genres: ['fantascienza', 'Avventura']),
        fav('a', year: 2016, genres: ['Avventura', 'Dramma']),
        fav('x', year: 2021),
        fav('n'),
      ]);
      expect(result.options.genres, ['Avventura', 'Dramma', 'fantascienza']);
      expect(result.options.years, [2021, 2016]);
    });

    test('la scelta attiva resta anche senza titoli', () {
      final result = view([fav('d', year: 2021, genres: ['Dramma'])],
          myListInitialFilters.copyWith(genres: {'Horror'}, year: 1990));
      expect(result.options.genres, ['Dramma', 'Horror']);
      expect(result.options.years, [2021, 1990]);
      expect(result.items, isEmpty);
    });

    test('i titoli tolti dal cuore non portano opzioni', () {
      final result = view([fav('d', year: 2021, genres: ['Dramma'])],
          myListInitialFilters, {'d': const UserItemData()});
      expect(result.options.genres, isEmpty);
      expect(result.options.years, isEmpty);
    });
  });
}
