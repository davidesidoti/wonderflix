import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';

/// Il plugin delle richieste finto: dati da preparare e chiamate registrate.
class FakeRequestsApi implements RequestsApi {
  RequestsMe meValue =
      const RequestsMe(canRequest: true, canManage: false, hasAccount: true);

  /// Risultati della ricerca per termine; un termine assente dà lista vuota.
  final searchResults = <String, List<RequestableTitle>>{};

  /// Schede per id TMDB; uno assente dà `invalid`.
  final titles = <int, TitleDetails>{};

  /// Se impostato, ogni chiamata lancia questo errore.
  RequestsFailure? failure;

  /// Errore solo per `create`.
  RequestsFailure? createFailure;

  /// Errore solo per `me`.
  RequestsFailure? meFailure;

  RequestStatus createdStatus = RequestStatus.pending;

  /// Se impostati, `search`, `create`, `title` e `me` aspettano che si
  /// completino.
  Completer<void>? searchGate;
  Completer<void>? createGate;
  Completer<void>? titleGate;
  Completer<void>? meGate;

  final calls = <String>[];
  final searchLanguages = <String>[];
  final created =
      <({RequestMediaType type, int tmdbId, List<int>? seasons})>[];

  void _fail() {
    final f = failure;
    if (f != null) throw RequestsException(f);
  }

  @override
  Future<RequestsMe> me() async {
    calls.add('me');
    final gate = meGate;
    if (gate != null) await gate.future;
    _fail();
    final f = meFailure;
    if (f != null) throw RequestsException(f);
    return meValue;
  }

  @override
  Future<List<RequestableTitle>> search(String query,
      {required String language, CancelToken? cancelToken}) async {
    calls.add('search:$query');
    searchLanguages.add(language);
    final gate = searchGate;
    if (gate != null) await gate.future;
    if (cancelToken?.isCancelled ?? false) {
      throw const RequestCancelledException();
    }
    _fail();
    return searchResults[query] ?? const [];
  }

  @override
  Future<TitleDetails> title(RequestMediaType type, int tmdbId,
      {required String language}) async {
    calls.add('title:${type.wire}:$tmdbId');
    final gate = titleGate;
    if (gate != null) await gate.future;
    _fail();
    final details = titles[tmdbId];
    if (details == null) {
      throw const RequestsException(RequestsFailure.invalid);
    }
    return details;
  }

  @override
  Future<CreatedRequest> create(RequestMediaType type, int tmdbId,
      {List<int>? seasons}) async {
    calls.add('create:${type.wire}:$tmdbId');
    created.add((type: type, tmdbId: tmdbId, seasons: seasons));
    final gate = createGate;
    if (gate != null) await gate.future;
    _fail();
    final f = createFailure;
    if (f != null) throw RequestsException(f);
    return CreatedRequest(id: 100, status: createdStatus);
  }

  @override
  Future<RequestPage> list(RequestsFilter filter,
      {required int skip, required int take, required String language}) async {
    calls.add('list:${filter.wire}:$skip');
    _fail();
    return const RequestPage(items: [], hasMore: false);
  }

  @override
  Future<List<ServiceOption>> services(RequestMediaType type) async {
    calls.add('services:${type.wire}');
    _fail();
    return const [];
  }

  @override
  Future<MediaRequest> approve(int requestId, ApproveChoice choice,
          {required String language}) =>
      throw UnimplementedError('piano 15b');

  @override
  Future<MediaRequest> decline(int requestId, {required String language}) =>
      throw UnimplementedError('piano 15b');
}

/// Provider per i test delle richieste: plugin [api], funzione [available].
List<Override> requestsTestOverrides(FakeRequestsApi api,
        {bool available = true}) =>
    [
      requestsApiProvider.overrideWithValue(api),
      requestsAvailableProvider.overrideWithValue(available),
    ];

RequestableTitle testRequestable({
  int tmdbId = 693134,
  String title = 'Dune - Parte due',
  RequestMediaType type = RequestMediaType.movie,
  int? year = 2024,
  TitleStatus status = TitleStatus.none,
  String? jellyfinItemId,
}) =>
    RequestableTitle(
      mediaType: type,
      tmdbId: tmdbId,
      title: title,
      year: year,
      posterPath: '/p$tmdbId.jpg',
      status: status,
      jellyfinItemId: jellyfinItemId,
    );

TitleDetails testDetails({
  int tmdbId = 693134,
  String title = 'Dune - Parte due',
  RequestMediaType type = RequestMediaType.movie,
  TitleStatus status = TitleStatus.none,
  String? jellyfinItemId,
  bool requestedByMe = false,
  bool requested = false,
  String? trailerUrl,
  List<SeasonInfo> seasons = const [],
}) =>
    TitleDetails(
      mediaType: type,
      tmdbId: tmdbId,
      title: title,
      year: 2024,
      overview: 'Paul Atreides si unisce ai Fremen.',
      genres: const ['Fantascienza', 'Avventura'],
      runtimeMinutes: type == RequestMediaType.movie ? 166 : null,
      posterPath: '/p$tmdbId.jpg',
      backdropPath: '/b$tmdbId.jpg',
      trailerUrl: trailerUrl,
      status: status,
      jellyfinItemId: jellyfinItemId,
      requestedByMe: requestedByMe,
      requested: requested,
      seasons: seasons,
    );
