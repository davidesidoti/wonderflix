import 'dart:async';

import 'package:dio/dio.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/core/jellyfin/library_api.dart';
import 'package:wonderflix/core/jellyfin/media_info_models.dart';

/// `LibraryApi` in memoria: risposte configurabili e chiamate registrate.
class FakeLibraryApi implements LibraryApi {
  ItemPage Function(ItemQuery query, int startIndex, int limit) onItems =
      (query, startIndex, limit) => const ItemPage([], 0);
  List<JellyfinItem> resumeItems = [];
  List<JellyfinItem> nextUpItems = [];
  final Map<String, JellyfinItem> itemsById = {};
  final Map<String, List<JellyfinItem>> seasonsBySeries = {};
  final Map<String, List<JellyfinItem>> episodesBySeason = {};
  List<JellyfinItem> similarItems = [];
  List<JellyfinItem> people = [];
  LibraryFilters libraryFilters = const LibraryFilters();

  /// Ultime visioni, per [playHistory].
  List<JellyfinItem> playHistoryItems = [];

  /// Il `limit` di ogni [playHistory].
  final playHistoryCalls = <int>[];

  /// Film visti, per [playedMovies].
  List<JellyfinItem> playedMovieItems = [];

  /// Il `limit` di ogni [playedMovies].
  final playedMoviesCalls = <int>[];

  /// Simili di ogni titolo; un titolo assente usa [similarItems].
  final Map<String, List<JellyfinItem>> similarById = {};

  /// Titolo e `limit` di ogni [similar].
  final similarCalls = <(String, int)>[];

  /// Se valorizzato, ogni chiamata lancia questo errore.
  Object? error;

  /// Ritardo simulato di ogni risposta.
  Duration delay = Duration.zero;

  /// Se valorizzato, le richieste dei preferiti (`favoritesOnly`, usate da
  /// `favoritesProvider`) aspettano che si completi.
  Completer<void>? favoritesGate;

  /// Se valorizzato, [itemsByIds] aspetta che si completi prima di
  /// rispondere (i dettagli dei titoli in coda arrivano dopo).
  Completer<void>? itemsByIdsGate;

  final itemQueries = <ItemQuery>[];
  /// Episodio successivo, per id dell'episodio corrente.
  final Map<String, JellyfinItem> nextEpisodes = {};

  /// Tutti gli episodi di ogni serie, in ordine (per [episodesFrom]).
  final Map<String, List<JellyfinItem>> seriesEpisodes = {};
  final episodesFromCalls =
      <({String seriesId, String startItemId, int limit})>[];

  /// Serie chieste ad [allEpisodes].
  final allEpisodesCalls = <String>[];

  /// Serie chieste a [seasons].
  final seasonsCalls = <String>[];

  /// Trailer locali, per id dell'elemento.
  final Map<String, List<JellyfinItem>> localTrailerItems = {};
  final nextEpisodeCalls = <String>[];

  /// Episodio precedente, per id dell'episodio corrente.
  final Map<String, JellyfinItem> previousEpisodes = {};
  final previousEpisodeCalls = <String>[];

  /// Id chiesti a [itemsByIds], una lista per chiamata.
  final itemsByIdsCalls = <List<String>>[];

  /// Titoli di ogni saga, in ordine (per [collectionItems]).
  final Map<String, List<JellyfinItem>> itemsByCollection = {};

  /// Saghe chieste a [collectionItems].
  final collectionItemsCalls = <String>[];

  /// Se valorizzato, [collectionItems] (solo lei) lancia questo errore.
  Object? collectionItemsError;

  /// Se valorizzato, [collectionItems] aspetta che si completi prima di
  /// rispondere (i titoli di una saga arrivano dopo la saga).
  Completer<void>? collectionItemsGate;

  /// Le risposte di [randomUnplayed], una per chiamata; l'ultima si ripete.
  final randomPages = <ItemPage>[];
  final randomCalls =
      <({Set<ItemKind> kinds, String? genre, double? minRating, int limit})>[];

  /// Se valorizzato, [randomUnplayed] aspetta che si completi.
  Completer<void>? randomGate;

  /// I generi per tipo; senza voce vale [libraryFilters].
  final filtersByKind = <ItemKind, LibraryFilters>{};
  final nextUpCutoffs = <DateTime?>[];
  final nextUpCalls = <String?>[];
  final favoriteCalls = <(String, bool)>[];
  final playedCalls = <(String, bool)>[];

  Future<T> _answer<T>(T Function() value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = error;
    if (failure != null) throw failure;
    return value();
  }

  @override
  Future<ItemPage> items(ItemQuery query,
      {required String userId,
      required int startIndex,
      required int limit,
      CancelToken? cancelToken}) async {
    itemQueries.add(query);
    final gate = query.favoritesOnly ? favoritesGate : null;
    if (gate != null) await gate.future;
    return _answer(() => onItems(query, startIndex, limit));
  }

  @override
  Future<ItemPage> randomUnplayed(String userId,
      {required Set<ItemKind> kinds,
      String? genre,
      double? minRating,
      required int limit}) async {
    randomCalls.add(
        (kinds: kinds, genre: genre, minRating: minRating, limit: limit));
    final gate = randomGate;
    if (gate != null) await gate.future;
    return _answer(() => randomPages.isEmpty
        ? const ItemPage([], 0)
        : randomPages.length > 1
            ? randomPages.removeAt(0)
            : randomPages.first);
  }

  @override
  Future<List<JellyfinItem>> resume(String userId, {int limit = 20}) =>
      _answer(() => resumeItems);

  @override
  Future<List<JellyfinItem>> nextUp(String userId,
      {String? seriesId,
      int limit = 20,
      bool enableResumable = false,
      DateTime? dateCutoff}) {
    nextUpCalls.add(seriesId);
    nextUpCutoffs.add(dateCutoff);
    return _answer(() => nextUpItems);
  }

  @override
  Future<JellyfinItem?> nextEpisode(
      String userId, String seriesId, String episodeId) {
    nextEpisodeCalls.add(episodeId);
    return _answer(() => nextEpisodes[episodeId]);
  }

  @override
  Future<JellyfinItem?> previousEpisode(
      String userId, String seriesId, String episodeId) {
    previousEpisodeCalls.add(episodeId);
    return _answer(() => previousEpisodes[episodeId]);
  }

  /// Gli elementi di [itemsById] tra [ids]; gli altri mancano, come quelli
  /// cancellati sul server.
  @override
  Future<List<JellyfinItem>> itemsByIds(
      String userId, List<String> ids) async {
    itemsByIdsCalls.add(ids);
    final gate = itemsByIdsGate;
    if (gate != null) await gate.future;
    return _answer(() => [
          for (final id in ids) ?itemsById[id],
        ]);
  }

  @override
  Future<List<JellyfinItem>> collectionItems(
      String userId, String collectionId) async {
    collectionItemsCalls.add(collectionId);
    final gate = collectionItemsGate;
    if (gate != null) await gate.future;
    return _answer(() {
      final failure = collectionItemsError;
      if (failure != null) throw failure;
      return itemsByCollection[collectionId] ?? const [];
    });
  }

  @override
  Future<List<JellyfinItem>> episodesFrom(
      String userId, String seriesId, String startItemId,
      {int limit = 50}) {
    episodesFromCalls
        .add((seriesId: seriesId, startItemId: startItemId, limit: limit));
    return _answer(() {
      final all = seriesEpisodes[seriesId] ?? const <JellyfinItem>[];
      final start = all.indexWhere((e) => e.id == startItemId);
      if (start < 0) return const <JellyfinItem>[];
      return all.skip(start).take(limit).toList();
    });
  }

  /// Gli episodi di [seriesEpisodes] (gli stessi di [episodesFrom]).
  @override
  Future<List<JellyfinItem>> allEpisodes(String userId, String seriesId) {
    allEpisodesCalls.add(seriesId);
    return _answer(() => seriesEpisodes[seriesId] ?? const []);
  }

  @override
  Future<List<JellyfinItem>> localTrailers(String userId, String itemId) =>
      _answer(() => localTrailerItems[itemId] ?? const []);

  @override
  Future<JellyfinItem> item(String userId, String itemId) =>
      _answer(() => itemsById[itemId] ?? (throw const NotFoundException()));

  /// Info tecniche per id; un titolo assente è 404.
  final Map<String, ItemMediaInfo> mediaInfoById = {};

  /// Titoli chiesti a [mediaInfo].
  final mediaInfoCalls = <String>[];

  @override
  Future<ItemMediaInfo> mediaInfo(String userId, String itemId) {
    mediaInfoCalls.add(itemId);
    return _answer(
        () => mediaInfoById[itemId] ?? (throw const NotFoundException()));
  }

  @override
  Future<List<JellyfinItem>> seasons(String userId, String seriesId) {
    seasonsCalls.add(seriesId);
    return _answer(() => seasonsBySeries[seriesId] ?? const []);
  }

  @override
  Future<List<JellyfinItem>> episodes(
          String userId, String seriesId, String seasonId) =>
      _answer(() => episodesBySeason[seasonId] ?? const []);

  @override
  Future<List<JellyfinItem>> similar(String userId, String itemId,
      {int limit = 12}) {
    similarCalls.add((itemId, limit));
    return _answer(() => similarById[itemId] ?? similarItems);
  }

  @override
  Future<List<JellyfinItem>> playHistory(String userId, {required int limit}) {
    playHistoryCalls.add(limit);
    return _answer(() => playHistoryItems);
  }

  @override
  Future<List<JellyfinItem>> playedMovies(String userId, {required int limit}) {
    playedMoviesCalls.add(limit);
    return _answer(() => playedMovieItems);
  }

  @override
  Future<LibraryFilters> filters(String userId, ItemKind kind) =>
      _answer(() => filtersByKind[kind] ?? libraryFilters);

  @override
  Future<List<JellyfinItem>> searchPeople(String userId, String term,
          {int limit = 12, CancelToken? cancelToken}) =>
      _answer(() => people);

  @override
  Future<UserItemData> setFavorite(String userId, String itemId,
      {required bool favorite}) {
    favoriteCalls.add((itemId, favorite));
    return _answer(() => UserItemData(isFavorite: favorite));
  }

  @override
  Future<UserItemData> setPlayed(String userId, String itemId,
      {required bool played}) {
    playedCalls.add((itemId, played));
    return _answer(() => UserItemData(played: played));
  }
}

/// Elemento di prova con immagini e dati utente configurabili.
JellyfinItem testItem({
  String id = 'm1',
  String name = 'Dune: Parte Due',
  ItemKind kind = ItemKind.movie,
  int? year = 2024,
  int? runtimeMinutes = 120,
  String? overview,
  bool played = false,
  bool favorite = false,
  int positionTicks = 0,
  double? playedPercentage,
  String? seriesId,
  String? seriesName,
  String? seasonId,
  int? index,
  int? seasonIndex,
  int? childCount,
  int? recursiveCount,
  int? unplayedCount,
  List<Map<String, dynamic>> people = const [],
  List<Map<String, dynamic>> trailers = const [],
  int localTrailers = 0,
  List<String> genres = const [],
  double? rating,
  String? sortName,
  String? dateCreated,
  String? premiereDate,
  int? tmdbId,
}) =>
    JellyfinItem.fromJson({
      'Id': id,
      'Name': name,
      'Type': kind == ItemKind.other ? 'Folder' : kind.apiName,
      'ProductionYear': ?year,
      'RunTimeTicks': ?(runtimeMinutes == null ? null : runtimeMinutes * 600000000),
      'Overview': ?overview,
      'ImageTags': {'Primary': 'p-$id'},
      'BackdropImageTags': ['b-$id'],
      'UserData': {
        'Played': played,
        'IsFavorite': favorite,
        'PlaybackPositionTicks': positionTicks,
        'PlayedPercentage': ?playedPercentage,
        'UnplayedItemCount': ?unplayedCount,
      },
      'SeriesId': ?seriesId,
      'SeriesName': ?seriesName,
      'SeasonId': ?seasonId,
      'IndexNumber': ?index,
      'ParentIndexNumber': ?seasonIndex,
      'ChildCount': ?childCount,
      'RecursiveItemCount': ?recursiveCount,
      'People': people,
      'RemoteTrailers': trailers,
      'LocalTrailerCount': localTrailers,
      if (genres.isNotEmpty) 'Genres': genres,
      'CommunityRating': ?rating,
      'SortName': ?sortName,
      'DateCreated': ?dateCreated,
      'PremiereDate': ?premiereDate,
      if (tmdbId != null) 'ProviderIds': {'Tmdb': '$tmdbId'},
    });

ItemPage pageOf(List<JellyfinItem> items, [int? total]) =>
    ItemPage(items, total ?? items.length);
