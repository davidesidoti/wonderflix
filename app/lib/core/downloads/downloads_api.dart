import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'download_models.dart';

final _log = Logger('downloads');

/// Perché una chiamata dei download automatici non è riuscita (spec T §8).
enum DownloadsFailure {
  /// 404: plugin senza la funzione.
  unavailable,

  /// 400, o risposta di forma inattesa.
  invalid,

  /// 401, 403: non ammesso.
  forbidden,

  /// 409 `Expired` (o motivo mancante/sconosciuto): la release non c'è più.
  expired,

  /// 409 `Busy`: un altro download dello stesso titolo è in corso.
  busy,

  /// 503 `Unavailable`: Radarr o Sonarr non rispondono.
  arrUnavailable,

  /// 502 `Refused`: Radarr o Sonarr hanno risposto con un errore (per esempio il client di download rifiuta il torrent).
  refused,

  /// Rete, timeout o errore del server.
  network,
}

class DownloadsException implements Exception {
  const DownloadsException(this.failure);

  final DownloadsFailure failure;

  @override
  String toString() => 'DownloadsException(${failure.name})';
}

/// Endpoint dei download automatici del plugin (spec T §8, solo admin).
/// Lancia solo [DownloadsException].
class DownloadsApi {
  DownloadsApi(this._http);

  static const _base = '/WonderFlixWatchParty/Downloads';

  /// La ricerca interroga gli indexer: può durare un paio di minuti.
  static const searchTimeout = Duration(seconds: 150);

  /// Esiti previsti: nel log come info, non tra gli "Ultimi errori".
  static const _quiet = {400, 403, 404, 409, 502, 503};

  final JellyfinHttp _http;

  Future<DownloadsOverview> overview() => _call(() async =>
      DownloadsOverview.fromJson(
          asJsonMap(await _http.get(_base, quietStatuses: _quiet))) ??
      (throw const ServerErrorException(null)));

  Future<DownloadSearch> search(String key, {CancelToken? cancelToken}) =>
      _call(() async =>
          DownloadSearch.fromJson(asJsonMap(await _http.get('$_base/Search',
              query: {'key': key},
              cancelToken: cancelToken,
              receiveTimeout: searchTimeout,
              quietStatuses: _quiet))) ??
          (throw const ServerErrorException(null)));

  /// [lighten]: dopo il grab il plugin toglie il file pesante (spec U §6.1).
  Future<void> grab(String key, String guid, int indexerId,
          {bool lighten = false}) =>
      _call(() => _http.post('$_base/Grab',
          body: {
            'Key': key,
            'Guid': guid,
            'IndexerId': indexerId,
            if (lighten) 'Lighten': true,
          },
          // Se Sonarr ha dimenticato le release il plugin le cerca di nuovo.
          receiveTimeout: searchTimeout,
          quietStatuses: _quiet));

  Future<void> accept(String key) => _call(() =>
      _http.post('$_base/Accept', body: {'Key': key}, quietStatuses: _quiet));

  Future<void> searchNow(String key) => _call(() => _http
      .post('$_base/SearchNow', body: {'Key': key}, quietStatuses: _quiet));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const DownloadsException(DownloadsFailure.unavailable);
    } on UnauthorizedException {
      throw const DownloadsException(DownloadsFailure.forbidden);
    } on ForbiddenException {
      throw const DownloadsException(DownloadsFailure.forbidden);
    } on ServerErrorException catch (error) {
      final reason = error.body is Map ? (error.body as Map)['Reason'] : null;
      throw DownloadsException(switch (error.statusCode) {
        400 => DownloadsFailure.invalid,
        409 => reason == 'Busy'
            ? DownloadsFailure.busy
            : DownloadsFailure.expired,
        502 when reason == 'Refused' => DownloadsFailure.refused,
        503 when reason == 'Unavailable' => DownloadsFailure.arrUnavailable,
        _ => DownloadsFailure.network,
      });
    } on ApiException {
      throw const DownloadsException(DownloadsFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta dei download non valida: ${error.runtimeType}');
      throw const DownloadsException(DownloadsFailure.network);
    }
  }
}
