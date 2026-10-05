import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'requests_models.dart';

final _log = Logger('requests');

/// Perché una chiamata delle richieste non è riuscita (spec I §7.3).
enum RequestsFailure {
  /// 404: plugin assente o vecchio.
  unavailable,

  /// 503: Seerr non configurato nel plugin.
  notConfigured,

  /// 502: Seerr irraggiungibile, lento o con la chiave rifiutata.
  seerrUnavailable,

  noPermission,
  quotaExceeded,
  blocklisted,
  alreadyRequested,

  /// Le stagioni scelte sono già tutte chieste o presenti.
  nothingToRequest,

  /// L'account Seerr dell'utente non si è potuto creare.
  accountUnavailable,

  /// 400: parametri sbagliati o richiesta che non c'è più.
  invalid,

  /// Rete, errore del server o risposta di forma inattesa.
  network,
}

class RequestsException implements Exception {
  const RequestsException(this.failure);

  final RequestsFailure failure;

  @override
  String toString() => 'RequestsException(${failure.name})';
}

/// Endpoint delle richieste del plugin (spec I §7.3). Lancia solo
/// [RequestsException], oppure [RequestCancelledException] per una ricerca
/// annullata.
class RequestsApi {
  RequestsApi(this._http);

  static const _base = '/WonderFlixWatchParty/Requests';

  /// Esiti previsti (Seerr giù, già chiesto, permessi): nel log come info,
  /// non tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {400, 403, 404, 409, 502, 503};

  final JellyfinHttp _http;

  Future<RequestsMe> me() => _call(() async => RequestsMe.fromJson(
      asJsonMap(await _http.get('$_base/Me', quietStatuses: _quiet))));

  /// Film e serie di Seerr per [query] (prima pagina). Le righe di un altro
  /// tipo (persone, tipi nuovi) si saltano.
  Future<List<RequestableTitle>> search(String query,
          {required String language, CancelToken? cancelToken}) =>
      _call(() async {
        final json = await _http.get('$_base/Search',
            query: {'query': query, 'language': language},
            cancelToken: cancelToken,
            quietStatuses: _quiet);
        return [
          for (final raw in json as List)
            if (!isUnknownMediaTypeRow(raw))
              RequestableTitle.fromJson(raw as Map<String, dynamic>),
        ];
      });

  Future<TitleDetails> title(RequestMediaType type, int tmdbId,
          {required String language}) =>
      _call(() async => TitleDetails.fromJson(asJsonMap(await _http.get(
          '$_base/${type == RequestMediaType.movie ? 'Movie' : 'Tv'}/$tmdbId',
          query: {'language': language},
          quietStatuses: _quiet))));

  /// Una richiesta; per le serie con le stagioni scelte.
  Future<CreatedRequest> create(RequestMediaType type, int tmdbId,
          {List<int>? seasons}) =>
      _call(() async => CreatedRequest.fromJson(asJsonMap(await _http.post(
          _base,
          body: {'MediaType': type.wire, 'TmdbId': tmdbId, 'Seasons': ?seasons},
          quietStatuses: _quiet))));

  Future<RequestPage> list(RequestsFilter filter,
          {required int skip, required int take, required String language}) =>
      _call(() async => RequestPage.fromJson(asJsonMap(await _http.get(_base,
          query: {
            'filter': filter.wire,
            'skip': skip,
            'take': take,
            'language': language,
          },
          quietStatuses: _quiet))));

  Future<List<ServiceOption>> services(RequestMediaType type) =>
      _call(() async {
        final json = await _http.get('$_base/Services/${type.wire}',
            quietStatuses: _quiet);
        return [
          for (final raw in json as List)
            ServiceOption.fromJson(raw as Map<String, dynamic>),
        ];
      });

  Future<MediaRequest> approve(int requestId, ApproveChoice choice,
          {required String language}) =>
      _call(() async => MediaRequest.fromJson(asJsonMap(await _http.post(
          '$_base/$requestId/Approve',
          body: choice.toJson(),
          query: {'language': language},
          quietStatuses: _quiet))));

  Future<MediaRequest> decline(int requestId, {required String language}) =>
      _call(() async => MediaRequest.fromJson(asJsonMap(await _http.post(
          '$_base/$requestId/Decline',
          query: {'language': language},
          quietStatuses: _quiet))));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on RequestCancelledException {
      rethrow;
    } on NotFoundException {
      throw const RequestsException(RequestsFailure.unavailable);
    } on UnauthorizedException {
      throw const RequestsException(RequestsFailure.noPermission);
    } on ForbiddenException catch (error) {
      throw RequestsException(switch (_code(error.body)) {
        'QuotaExceeded' => RequestsFailure.quotaExceeded,
        'Blocklisted' => RequestsFailure.blocklisted,
        _ => RequestsFailure.noPermission,
      });
    } on ServerErrorException catch (error) {
      throw RequestsException(switch ((error.statusCode, _code(error.body))) {
        (409, 'AlreadyRequested') => RequestsFailure.alreadyRequested,
        (409, 'NothingToRequest') => RequestsFailure.nothingToRequest,
        (409, 'AccountUnavailable') => RequestsFailure.accountUnavailable,
        (400, _) => RequestsFailure.invalid,
        (502, _) => RequestsFailure.seerrUnavailable,
        (503, _) => RequestsFailure.notConfigured,
        _ => RequestsFailure.network,
      });
    } on ApiException {
      throw const RequestsException(RequestsFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta delle richieste non valida: ${error.runtimeType}');
      throw const RequestsException(RequestsFailure.network);
    }
  }

  static String? _code(Object? body) {
    if (body is! Map) return null;
    final code = body['Code'];
    return code is String ? code : null;
  }
}
