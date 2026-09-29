import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';

void main() {
  test('parametri di base', () {
    final params = const ItemQuery(kinds: {ItemKind.movie})
        .toQueryParameters(userId: 'u1', startIndex: 100, limit: 50);
    expect(params['userId'], 'u1');
    expect(params['recursive'], true);
    expect(params['includeItemTypes'], 'Movie');
    expect(params['sortBy'], 'SortName');
    expect(params['sortOrder'], 'Ascending');
    expect(params['startIndex'], 100);
    expect(params['limit'], 50);
    expect(params['enableTotalRecordCount'], true);
    expect(params.containsKey('genres'), isFalse);
    expect(params.containsKey('isPlayed'), isFalse);
  });

  test('filtri, ordinamento e ricerca', () {
    final params = const ItemQuery(
      kinds: {ItemKind.series, ItemKind.movie},
      sort: CatalogSort.year,
      genres: {'Dramma', 'Azione'},
      year: 2023,
      watched: WatchedFilter.unwatched,
      favoritesOnly: true,
      searchTerm: 'dune',
      personId: 'p9',
    ).toQueryParameters(userId: 'u1', startIndex: 0, limit: 20);
    expect(params['includeItemTypes'], 'Movie,Series');
    expect(params['sortBy'], 'ProductionYear,SortName');
    expect(params['sortOrder'], 'Descending');
    expect(params['genres'], 'Azione|Dramma');
    expect(params['years'], '2023');
    expect(params['isPlayed'], false);
    expect(params['isFavorite'], true);
    expect(params['searchTerm'], 'dune');
    expect(params['personIds'], 'p9');
  });

  test('data di aggiunta: per le serie usa l\'ultimo contenuto aggiunto', () {
    Map<String, dynamic> p(Set<ItemKind> kinds) =>
        ItemQuery(kinds: kinds, sort: CatalogSort.dateAdded)
            .toQueryParameters(userId: 'u', startIndex: 0, limit: 1);
    expect(p({ItemKind.movie})['sortBy'], 'DateCreated,SortName');
    expect(p({ItemKind.series})['sortBy'], 'DateLastContentAdded,SortName');
  });

  test('copyWith e hasFilters', () {
    const base = ItemQuery(kinds: {ItemKind.movie});
    expect(base.hasFilters, isFalse);
    final filtered = base.copyWith(year: 2020, watched: WatchedFilter.watched);
    expect(filtered.hasFilters, isTrue);
    expect(filtered.copyWith(year: null).year, isNull);
    expect(filtered.copyWith(sort: CatalogSort.rating).year, 2020);
  });
}
