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
    expect(params['sortOrder'], 'Descending,Ascending');
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

  test('ordinamenti a due chiavi: un ordine per chiave', () {
    for (final sort in [
      CatalogSort.dateAdded,
      CatalogSort.year,
      CatalogSort.rating,
    ]) {
      final params = ItemQuery(kinds: const {ItemKind.movie}, sort: sort)
          .toQueryParameters(userId: 'u', startIndex: 0, limit: 1);
      expect(params['sortOrder'], 'Descending,Ascending', reason: '$sort');
    }
  });

  test('copyWith e hasFilters', () {
    const base = ItemQuery(kinds: {ItemKind.movie});
    expect(base.hasFilters, isFalse);
    final filtered = base.copyWith(year: 2020, watched: WatchedFilter.watched);
    expect(filtered.hasFilters, isTrue);
    expect(filtered.copyWith(year: null).year, isNull);
    expect(filtered.copyWith(sort: CatalogSort.rating).year, 2020);
  });

  test('campi per ordinare nell\'app solo se richiesti', () {
    Map<String, dynamic> p(ItemQuery q) =>
        q.toQueryParameters(userId: 'u', startIndex: 0, limit: 1);
    expect(p(const ItemQuery(kinds: {ItemKind.movie}))['fields'],
        'PrimaryImageAspectRatio,Genres');
    expect(
        p(const ItemQuery(kinds: {ItemKind.movie}, includeSortFields: true))[
            'fields'],
        'PrimaryImageAspectRatio,Genres,SortName,DateCreated,'
        'RecursiveItemCount,DateLastMediaAdded');
    expect(
        const ItemQuery(kinds: {ItemKind.movie}, includeSortFields: true)
            .copyWith(year: 2020)
            .includeSortFields,
        isTrue);
  });

  test('ProviderIds solo se richiesti, anche insieme ai campi per ordinare', () {
    Map<String, dynamic> p(ItemQuery q) =>
        q.toQueryParameters(userId: 'u', startIndex: 0, limit: 1);
    expect(p(const ItemQuery(kinds: {ItemKind.movie}))['fields'],
        isNot(contains('ProviderIds')));
    expect(
        p(const ItemQuery(kinds: {ItemKind.movie}, includeProviderIds: true))[
            'fields'],
        'PrimaryImageAspectRatio,Genres,ProviderIds');
    expect(
        p(const ItemQuery(
            kinds: {ItemKind.movie},
            includeSortFields: true,
            includeProviderIds: true))['fields'],
        'PrimaryImageAspectRatio,Genres,SortName,DateCreated,'
        'RecursiveItemCount,DateLastMediaAdded,ProviderIds');
    expect(
        const ItemQuery(kinds: {ItemKind.movie}, includeProviderIds: true)
            .copyWith(year: 2020)
            .includeProviderIds,
        isTrue);
  });

  test('clearFilters toglie solo genere, anno e visti', () {
    const query = ItemQuery(
      kinds: {ItemKind.movie, ItemKind.series},
      sort: CatalogSort.year,
      genres: {'Dramma'},
      year: 2020,
      watched: WatchedFilter.watched,
      favoritesOnly: true,
      searchTerm: 'dune',
      personId: 'p9',
      includeSortFields: true,
      includeProviderIds: true,
    );
    final cleared = query.clearFilters();
    expect(cleared.hasFilters, isFalse);
    expect(cleared.genres, isEmpty);
    expect(cleared.year, isNull);
    expect(cleared.watched, WatchedFilter.all);
    expect(cleared.kinds, {ItemKind.movie, ItemKind.series});
    expect(cleared.sort, CatalogSort.year);
    expect(cleared.favoritesOnly, isTrue);
    expect(cleared.searchTerm, 'dune');
    expect(cleared.personId, 'p9');
    expect(cleared.includeSortFields, isTrue);
    expect(cleared.includeProviderIds, isTrue);
  });

  group('sala per genere', () {
    Map<String, dynamic> p(ItemQuery q) =>
        q.toQueryParameters(userId: 'u', startIndex: 0, limit: 1);
    const movies = ItemQuery(kinds: {ItemKind.movie});

    test('decennio: anni separati da virgola', () {
      expect(p(movies.copyWith(decade: 2010))['years'],
          '2010,2011,2012,2013,2014,2015,2016,2017,2018,2019');
      final older = p(movies.copyWith(decade: ItemQuery.olderDecades))['years']
          as String;
      final years = older.split(',');
      expect(years.length, 90);
      expect(years.first, '1900');
      expect(years.last, '1989');
      expect(p(movies).containsKey('years'), isFalse);
    });

    test('stato delle serie', () {
      expect(p(movies.copyWith(seriesStatus: SeriesStatusFilter.continuing))[
          'seriesStatus'], 'Continuing');
      expect(p(movies.copyWith(seriesStatus: SeriesStatusFilter.ended))[
          'seriesStatus'], 'Ended');
      expect(p(movies).containsKey('seriesStatus'), isFalse);
    });

    test('verso invertito: solo la prima chiave', () {
      expect(p(movies.copyWith(sort: CatalogSort.rating, reversed: true))[
          'sortOrder'], 'Ascending,Ascending');
      expect(p(movies.copyWith(sort: CatalogSort.title, reversed: true))[
          'sortOrder'], 'Descending');
      const series = ItemQuery(kinds: {ItemKind.series});
      final added = p(series.copyWith(sort: CatalogSort.dateAdded));
      expect(added['sortBy'], 'DateLastContentAdded,SortName');
      expect(added['sortOrder'], 'Descending,Ascending');
    });

    test('ricerca in copyWith, raffinamenti', () {
      final q = movies.copyWith(searchTerm: 'dune');
      expect(p(q)['searchTerm'], 'dune');
      expect(q.copyWith(searchTerm: null).searchTerm, isNull);
      expect(q.copyWith(sort: CatalogSort.year).searchTerm, 'dune');

      expect(movies.hasRefinements, isFalse);
      expect(movies.copyWith(searchTerm: '').hasRefinements, isFalse);
      final refined = movies.copyWith(
        genres: {'Dramma'},
        sort: CatalogSort.rating,
        reversed: true,
        decade: 2010,
        seriesStatus: SeriesStatusFilter.ended,
        watched: WatchedFilter.watched,
        searchTerm: 'dune',
      );
      expect(refined.hasRefinements, isTrue);
      final cleared = refined.clearRefinements();
      expect(cleared.hasRefinements, isFalse);
      expect(cleared.decade, isNull);
      expect(cleared.seriesStatus, SeriesStatusFilter.all);
      expect(cleared.watched, WatchedFilter.all);
      expect(cleared.searchTerm, isNull);
      expect(cleared.genres, {'Dramma'});
      expect(cleared.sort, CatalogSort.rating);
      expect(cleared.reversed, isTrue);
      expect(cleared.kinds, {ItemKind.movie});
    });

    test('hasFilters non conta i campi nuovi (La mia lista)', () {
      expect(
          movies
              .copyWith(
                  decade: 2010,
                  seriesStatus: SeriesStatusFilter.ended,
                  searchTerm: 'x')
              .hasFilters,
          isFalse);
    });
  });
}
