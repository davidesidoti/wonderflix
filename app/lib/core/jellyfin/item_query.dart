import 'item_models.dart';

enum CatalogSort { title, dateAdded, year, rating }

enum WatchedFilter { all, unwatched, watched }

enum SeriesStatusFilter { all, continuing, ended }

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
    this.decade,
    this.seriesStatus = SeriesStatusFilter.all,
    this.reversed = false,
    this.watched = WatchedFilter.all,
    this.favoritesOnly = false,
    this.searchTerm,
    this.personId,
    this.includeSortFields = false,
    this.includeProviderIds = false,
  });

  final Set<ItemKind> kinds;
  final CatalogSort sort;
  final Set<String> genres;
  final int? year;

  /// Anno di inizio del decennio (2020, 2010, ...) o [olderDecades].
  final int? decade;
  final SeriesStatusFilter seriesStatus;

  /// Inverte l'ordine della prima chiave di [sort].
  final bool reversed;
  final WatchedFilter watched;
  final bool favoritesOnly;
  final String? searchTerm;
  final String? personId;

  /// Chiede anche `SortName` e `DateCreated`, per ordinare nell'app
  /// (La mia lista).
  final bool includeSortFields;

  /// Chiede anche `ProviderIds`, per avere l'id TMDB degli elementi
  /// (`JellyfinItem.tmdbId`): la ricerca lo usa per non ripetere in
  /// "Da richiedere" i titoli che la libreria ha già.
  final bool includeProviderIds;

  /// Valore di [decade] per "Prima" (prima del 1990).
  static const olderDecades = 0;

  /// Filtri scelti dall'utente nel catalogo (esclusi ordinamento e tipo).
  bool get hasFilters =>
      genres.isNotEmpty || year != null || watched != WatchedFilter.all;

  /// Raffinamenti della sala (decennio, stato, visti, ricerca): generi,
  /// tipi e ordine non contano.
  bool get hasRefinements =>
      decade != null ||
      seriesStatus != SeriesStatusFilter.all ||
      watched != WatchedFilter.all ||
      (searchTerm ?? '').isNotEmpty;

  ItemQuery copyWith({
    CatalogSort? sort,
    Set<String>? genres,
    Object? year = _keep,
    Object? decade = _keep,
    SeriesStatusFilter? seriesStatus,
    bool? reversed,
    WatchedFilter? watched,
    Object? searchTerm = _keep,
  }) =>
      ItemQuery(
        kinds: kinds,
        sort: sort ?? this.sort,
        genres: genres ?? this.genres,
        year: identical(year, _keep) ? this.year : year as int?,
        decade: identical(decade, _keep) ? this.decade : decade as int?,
        seriesStatus: seriesStatus ?? this.seriesStatus,
        reversed: reversed ?? this.reversed,
        watched: watched ?? this.watched,
        favoritesOnly: favoritesOnly,
        searchTerm: identical(searchTerm, _keep)
            ? this.searchTerm
            : searchTerm as String?,
        personId: personId,
        includeSortFields: includeSortFields,
        includeProviderIds: includeProviderIds,
      );

  /// Toglie genere, anno e visti; il resto (tipi, ordinamento, preferiti,
  /// ricerca, persona, campi) resta. Passa da [copyWith]: un campo nuovo non
  /// si dimentica qui.
  ItemQuery clearFilters() =>
      copyWith(genres: const {}, year: null, watched: WatchedFilter.all);

  /// Toglie decennio, stato delle serie, visti e ricerca; tipi, generi,
  /// ordine e verso restano.
  ItemQuery clearRefinements() => copyWith(
        decade: null,
        seriesStatus: SeriesStatusFilter.all,
        watched: WatchedFilter.all,
        searchTerm: null,
      );

  Map<String, dynamic> toQueryParameters({
    required String userId,
    required int startIndex,
    required int limit,
  }) {
    final onlySeries = kinds.length == 1 && kinds.contains(ItemKind.series);
    // Jellyfin applica il primo `sortOrder` a ogni chiave senza un ordine
    // proprio: per gli ordinamenti a due chiavi ne serve uno per chiave.
    final (sortBy, baseOrder) = switch (sort) {
      CatalogSort.title => ('SortName', 'Ascending'),
      CatalogSort.dateAdded => (
          onlySeries ? 'DateLastContentAdded,SortName' : 'DateCreated,SortName',
          'Descending,Ascending'
        ),
      CatalogSort.year => ('ProductionYear,SortName', 'Descending,Ascending'),
      CatalogSort.rating => ('CommunityRating,SortName', 'Descending,Ascending'),
    };
    // Il verso inverso tocca solo la prima chiave (SortName resta A-Z).
    final sortOrder = !reversed
        ? baseOrder
        : baseOrder.startsWith('Descending')
            ? baseOrder.replaceFirst('Descending', 'Ascending')
            : baseOrder.replaceFirst('Ascending', 'Descending');
    final term = searchTerm;
    final d = decade;
    final decadeYears = d == null
        ? null
        : d == olderDecades
            ? [for (var y = 1900; y < 1990; y++) y]
            : [for (var y = d; y < d + 10; y++) y];
    return {
      ...cardImageParams,
      if (includeSortFields || includeProviderIds)
        'fields': [
          cardImageParams['fields'],
          if (includeSortFields) 'SortName,DateCreated',
          if (includeProviderIds) 'ProviderIds',
        ].join(','),
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
      if (decadeYears != null) 'years': decadeYears.join(','),
      if (seriesStatus == SeriesStatusFilter.continuing)
        'seriesStatus': 'Continuing',
      if (seriesStatus == SeriesStatusFilter.ended) 'seriesStatus': 'Ended',
      if (watched == WatchedFilter.unwatched) 'isPlayed': false,
      if (watched == WatchedFilter.watched) 'isPlayed': true,
      if (favoritesOnly) 'isFavorite': true,
      if (term != null && term.isNotEmpty) 'searchTerm': term,
      if (personId != null) 'personIds': personId,
    };
  }
}
