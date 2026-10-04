import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'item_models.dart';
import 'item_query.dart';
import 'jellyfin_http.dart';

/// Endpoint della libreria (Jellyfin 10.11). Lancia solo `ApiException`.
class LibraryApi {
  LibraryApi(this._http);

  final JellyfinHttp _http;

  Future<ItemPage> items(
    ItemQuery query, {
    required String userId,
    required int startIndex,
    required int limit,
    CancelToken? cancelToken,
  }) async {
    final data = await _http.get('/Items',
        query: query.toQueryParameters(
            userId: userId, startIndex: startIndex, limit: limit),
        cancelToken: cancelToken);
    return parseJson(
        data,
        (json) => ItemPage(
            _items(json), (json['TotalRecordCount'] as num?)?.toInt() ?? 0));
  }

  Future<List<JellyfinItem>> resume(String userId, {int limit = 20}) async =>
      _list(await _http.get('/UserItems/Resume', query: {
        ...cardImageParams,
        'userId': userId,
        'limit': limit,
        'mediaTypes': 'Video',
        'includeItemTypes': 'Movie,Episode',
      }));

  /// [dateCutoff]: ignora le serie non guardate da prima di questa data.
  Future<List<JellyfinItem>> nextUp(
    String userId, {
    String? seriesId,
    int limit = 20,
    bool enableResumable = false,
    DateTime? dateCutoff,
  }) async =>
      _list(await _http.get('/Shows/NextUp', query: {
        ...cardImageParams,
        'userId': userId,
        'limit': limit,
        'enableResumable': enableResumable,
        'seriesId': ?seriesId,
        'nextUpDateCutoff': ?dateCutoff?.toUtc().toIso8601String(),
      }));

  Future<JellyfinItem> item(String userId, String itemId) async => parseJson(
      await _http.get('/Items/$itemId', query: {'userId': userId}),
      JellyfinItem.fromJson);

  Future<List<JellyfinItem>> seasons(String userId, String seriesId) async =>
      _list(await _http.get('/Shows/$seriesId/Seasons',
          query: {...cardImageParams, 'userId': userId}));

  Future<List<JellyfinItem>> episodes(
          String userId, String seriesId, String seasonId) async =>
      _list(await _http.get('/Shows/$seriesId/Episodes', query: {
        ...cardImageParams,
        'userId': userId,
        'seasonId': seasonId,
        'fields': 'Overview,PrimaryImageAspectRatio',
      }));

  /// Tutti gli episodi veri della serie, in ordine e con le immagini delle
  /// card (spec H §9.2, viste Serie e Stagione): senza i mancanti, che non
  /// si possono guardare.
  Future<List<JellyfinItem>> allEpisodes(String userId, String seriesId) async =>
      _list(await _http.get('/Shows/$seriesId/Episodes', query: {
        ...cardImageParams,
        'userId': userId,
        'isMissing': false,
      }));

  /// Episodio che segue [episodeId] nella serie, anche nella stagione dopo;
  /// `null` se è l'ultimo.
  Future<JellyfinItem?> nextEpisode(
      String userId, String seriesId, String episodeId) async {
    final episodes = _list(await _http.get('/Shows/$seriesId/Episodes', query: {
      ...cardImageParams,
      'userId': userId,
      'startItemId': episodeId,
      'limit': 2,
      'isMissing': false,
      'fields': 'Overview,PrimaryImageAspectRatio',
    }));
    final index = episodes.indexWhere((e) => e.id == episodeId);
    return index >= 0 && index + 1 < episodes.length ? episodes[index + 1] : null;
  }

  /// Episodio che precede [episodeId] nella serie, anche nella stagione
  /// prima (spec H §8.1); `null` se è il primo. Jellyfin toglie i mancanti
  /// prima di cercare i vicini.
  Future<JellyfinItem?> previousEpisode(
      String userId, String seriesId, String episodeId) async {
    final episodes = _list(await _http.get('/Shows/$seriesId/Episodes', query: {
      ...cardImageParams,
      'userId': userId,
      'adjacentTo': episodeId,
      'isMissing': false,
      'fields': 'Overview,PrimaryImageAspectRatio',
    }));
    final index = episodes.indexWhere((e) => e.id == episodeId);
    return index > 0 ? episodes[index - 1] : null;
  }

  /// Gli elementi [ids] (la coda del watch party, spec H §8.5), in ordine
  /// qualunque: quelli cancellati o che l'utente non vede mancano. Con la
  /// sinossi (`Overview`, che Jellyfin manda solo se richiesta): serve al
  /// post-play del party. Con [ids] vuoto non parte nessuna richiesta: un
  /// `ids=` vuoto farebbe rispondere a Jellyfin con le viste della libreria.
  Future<List<JellyfinItem>> itemsByIds(
      String userId, List<String> ids) async {
    if (ids.isEmpty) return const [];
    return _list(await _http.get('/Items', query: {
      ...cardImageParams,
      'fields': '${cardImageParams['fields']},Overview',
      'userId': userId,
      'ids': ids.join(','),
    }));
  }

  /// [startItemId] e gli episodi che lo seguono nella serie, anche nelle
  /// stagioni dopo (al massimo [limit]); senza gli episodi mancanti. Solo i
  /// dati di base (servono gli id): niente immagini, dati utente e campi in
  /// più.
  Future<List<JellyfinItem>> episodesFrom(
          String userId, String seriesId, String startItemId,
          {int limit = 50}) async =>
      _list(await _http.get('/Shows/$seriesId/Episodes', query: {
        'userId': userId,
        'startItemId': startItemId,
        'limit': limit,
        'isMissing': false,
        'enableImages': false,
        'enableUserData': false,
      }));

  /// Trailer salvati sul server accanto all'elemento.
  Future<List<JellyfinItem>> localTrailers(String userId, String itemId) async {
    final data = await _http
        .get('/Items/$itemId/LocalTrailers', query: {'userId': userId});
    if (data is! List) throw const ServerErrorException(null);
    return data
        .whereType<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .toList();
  }

  Future<List<JellyfinItem>> similar(String userId, String itemId,
          {int limit = 12}) async =>
      _list(await _http.get('/Items/$itemId/Similar',
          query: {...cardImageParams, 'userId': userId, 'limit': limit}));

  Future<LibraryFilters> filters(String userId, ItemKind kind) async =>
      parseJson(
        await _http.get('/Items/Filters',
            query: {'userId': userId, 'includeItemTypes': kind.apiName}),
        (json) => LibraryFilters(
          genres: (json['Genres'] as List? ?? const []).cast<String>().toList(),
          years: (json['Years'] as List? ?? const [])
              .map((y) => (y as num).toInt())
              .toList()
            ..sort((a, b) => b.compareTo(a)),
        ),
      );

  Future<List<JellyfinItem>> searchPeople(
    String userId,
    String term, {
    int limit = 12,
    CancelToken? cancelToken,
  }) async =>
      _list(await _http.get('/Persons',
          query: {'userId': userId, 'searchTerm': term, 'limit': limit},
          cancelToken: cancelToken));

  Future<UserItemData> setFavorite(String userId, String itemId,
          {required bool favorite}) =>
      _toggle('/UserFavoriteItems/$itemId', userId, favorite);

  Future<UserItemData> setPlayed(String userId, String itemId,
          {required bool played}) =>
      _toggle('/UserPlayedItems/$itemId', userId, played);

  Future<UserItemData> _toggle(String path, String userId, bool on) async {
    final query = {'userId': userId};
    final data = on
        ? await _http.post(path, query: query)
        : await _http.delete(path, query: query);
    return parseJson(data, UserItemData.fromJson);
  }
}

List<JellyfinItem> _items(Map<String, dynamic> json) =>
    (json['Items'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .toList();

List<JellyfinItem> _list(Object? data) => parseJson(data, _items);
