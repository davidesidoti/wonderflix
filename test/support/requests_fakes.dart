import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

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

  /// Le richieste di ogni elenco, in ordine: `list` ne dà una pagina.
  final lists = <RequestsFilter, List<MediaRequest>>{};

  /// Se impostato, `list` aspetta che si completi.
  Completer<void>? listGate;

  /// I server per tipo di titolo.
  final servicesByType = <RequestMediaType, List<ServiceOption>>{};

  /// Errore solo per `services`.
  RequestsFailure? servicesFailure;

  /// Errore solo per `approve` e `decline`.
  RequestsFailure? actionFailure;

  /// Se impostato, `approve` e `decline` aspettano che si completi.
  Completer<void>? actionGate;

  final approved = <({int id, ApproveChoice choice})>[];
  final declined = <int>[];

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
    calls.add('list:${filter.wire}:$skip:$take');
    final gate = listGate;
    if (gate != null) await gate.future;
    _fail();
    final all = lists[filter] ?? const <MediaRequest>[];
    final page = all.skip(skip).take(take).toList();
    return RequestPage(items: page, hasMore: skip + page.length < all.length);
  }

  @override
  Future<List<ServiceOption>> services(RequestMediaType type) async {
    calls.add('services:${type.wire}');
    _fail();
    final f = servicesFailure;
    if (f != null) throw RequestsException(f);
    return servicesByType[type] ?? const [];
  }

  @override
  Future<MediaRequest> approve(int requestId, ApproveChoice choice,
      {required String language}) async {
    calls.add('approve:$requestId');
    approved.add((id: requestId, choice: choice));
    return _act(requestId, RequestStatus.approved);
  }

  @override
  Future<MediaRequest> decline(int requestId, {required String language}) async {
    calls.add('decline:$requestId');
    declined.add(requestId);
    return _act(requestId, RequestStatus.declined);
  }

  Future<MediaRequest> _act(int requestId, RequestStatus status) async {
    final gate = actionGate;
    if (gate != null) await gate.future;
    _fail();
    final f = actionFailure;
    if (f != null) throw RequestsException(f);
    return testMediaRequest(id: requestId, status: status);
  }
}

/// Provider per i test delle richieste: plugin [api], funzione
/// [available], avvisi della cassetta da [events].
List<Override> requestsTestOverrides(FakeRequestsApi api,
        {bool available = true,
        Stream<SocialEvent> events = const Stream.empty()}) =>
    [
      requestsApiProvider.overrideWithValue(api),
      requestsAvailableProvider.overrideWithValue(available),
      socialEventsProvider.overrideWithValue(events),
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

MediaRequest testMediaRequest({
  int id = 1,
  String title = 'Dune - Parte due',
  RequestMediaType type = RequestMediaType.movie,
  int? year = 2024,
  List<int> seasons = const [],
  String requester = 'Mario',
  bool isMe = false,
  RequestStatus status = RequestStatus.pending,
  double? progress,
  String? jellyfinItemId,
  DateTime? createdAt,
}) =>
    MediaRequest(
      id: id,
      mediaType: type,
      tmdbId: 693000 + id,
      title: title,
      year: year,
      posterPath: '/r$id.jpg',
      seasons: seasons,
      requestedBy: Requester(name: requester, isMe: isMe),
      createdAt: createdAt ?? DateTime.utc(2026, 10, 3, 20),
      status: status,
      progress: progress,
      jellyfinItemId: jellyfinItemId,
    );
