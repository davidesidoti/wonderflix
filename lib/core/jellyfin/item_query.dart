import 'item_models.dart';

enum CatalogSort { title, dateAdded, year, rating }

enum WatchedFilter { all, unwatched, watched }

/// Parametri immagine/campi comuni a tutte le liste mostrate come card.
const cardImageParams = <String, dynamic>{
  'fields': 'PrimaryImageAspectRatio,Genres',
  'enableImageTypes': 'Primary,Backdrop,Thumb,Logo',
  'imageTypeLimit': 1,
};

const Object _keep = Object();

/// Interrogazione di `GET /Items` (catalogo, preferiti, ricerca, filmografia).
class ItemQuery {
  const ItemQuery({
    required this.kinds,
    this.sort = CatalogSort.title,
    this.genres = const {},
    this.year,
    this.watched = WatchedFilter.all,
    this.favoritesOnly = false,
    this.searchTerm,
    this.personId,
  });

  final Set<ItemKind> kinds;
  final CatalogSort sort;
  final Set<String> genres;
  final int? year;
  final WatchedFilter watched;
  final bool favoritesOnly;
  final String? searchTerm;
  final String? personId;

  /// Filtri scelti dall'utente nel catalogo (esclusi ordinamento e tipo).
  bool get hasFilters =>
      genres.isNotEmpty || year != null || watched != WatchedFilter.all;

  ItemQuery copyWith({
    CatalogSort? sort,
    Set<String>? genres,
    Object? year = _keep,
    WatchedFilter? watched,
  }) =>
      ItemQuery(
        kinds: kinds,
        sort: sort ?? this.sort,
        genres: genres ?? this.genres,
        year: identical(year, _keep) ? this.year : year as int?,
        watched: watched ?? this.watched,
        favoritesOnly: favoritesOnly,
        searchTerm: searchTerm,
        personId: personId,
      );

  Map<String, dynamic> toQueryParameters({
    required String userId,
    required int startIndex,
    required int limit,
  }) {
    final onlySeries = kinds.length == 1 && kinds.contains(ItemKind.series);
    // Jellyfin applica il primo `sortOrder` a ogni chiave senza un ordine
    // proprio: per gli ordinamenti a due chiavi ne serve uno per chiave.
    final (sortBy, sortOrder) = switch (sort) {
      CatalogSort.title => ('SortName', 'Ascending'),
      CatalogSort.dateAdded => (
          onlySeries ? 'DateLastContentAdded,SortName' : 'DateCreated,SortName',
          'Descending,Ascending'
        ),
      CatalogSort.year => ('ProductionYear,SortName', 'Descending,Ascending'),
      CatalogSort.rating => ('CommunityRating,SortName', 'Descending,Ascending'),
    };
    final term = searchTerm;
    return {
      ...cardImageParams,
      'userId': userId,
      'recursive': true,
      'includeItemTypes': (kinds.map((k) => k.apiName).toList()..sort()).join(','),
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      'startIndex': startIndex,
      'limit': limit,
      'enableTotalRecordCount': true,
      if (genres.isNotEmpty) 'genres': (genres.toList()..sort()).join('|'),
      if (year != null) 'years': '$year',
      if (watched == WatchedFilter.unwatched) 'isPlayed': false,
      if (watched == WatchedFilter.watched) 'isPlayed': true,
      if (favoritesOnly) 'isFavorite': true,
      if (term != null && term.isNotEmpty) 'searchTerm': term,
      if (personId != null) 'personIds': personId,
    };
  }
}
