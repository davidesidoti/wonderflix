import 'package:dio/dio.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/core/jellyfin/library_api.dart';

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

  /// Se valorizzato, ogni chiamata lancia questo errore.
  Object? error;

  /// Ritardo simulato di ogni risposta.
  Duration delay = Duration.zero;

  final itemQueries = <ItemQuery>[];
  /// Episodio successivo, per id dell'episodio corrente.
  final Map<String, JellyfinItem> nextEpisodes = {};

  /// Trailer locali, per id dell'elemento.
  final Map<String, List<JellyfinItem>> localTrailerItems = {};
  final nextEpisodeCalls = <String>[];
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
      CancelToken? cancelToken}) {
    itemQueries.add(query);
    return _answer(() => onItems(query, startIndex, limit));
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
  Future<List<JellyfinItem>> localTrailers(String userId, String itemId) =>
      _answer(() => localTrailerItems[itemId] ?? const []);

  @override
  Future<JellyfinItem> item(String userId, String itemId) =>
      _answer(() => itemsById[itemId] ?? (throw const NotFoundException()));

  @override
  Future<List<JellyfinItem>> seasons(String userId, String seriesId) =>
      _answer(() => seasonsBySeries[seriesId] ?? const []);

  @override
  Future<List<JellyfinItem>> episodes(
          String userId, String seriesId, String seasonId) =>
      _answer(() => episodesBySeason[seasonId] ?? const []);

  @override
  Future<List<JellyfinItem>> similar(String userId, String itemId,
          {int limit = 12}) =>
      _answer(() => similarItems);

  @override
  Future<LibraryFilters> filters(String userId, ItemKind kind) =>
      _answer(() => libraryFilters);

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
  List<Map<String, dynamic>> people = const [],
  List<Map<String, dynamic>> trailers = const [],
  int localTrailers = 0,
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
      },
      'SeriesId': ?seriesId,
      'SeriesName': ?seriesName,
      'SeasonId': ?seasonId,
      'IndexNumber': ?index,
      'ParentIndexNumber': ?seasonIndex,
      'ChildCount': ?childCount,
      'People': people,
      'RemoteTrailers': trailers,
      'LocalTrailerCount': localTrailers,
    });

ItemPage pageOf(List<JellyfinItem> items, [int? total]) =>
    ItemPage(items, total ?? items.length);
