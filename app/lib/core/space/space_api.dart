import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'space_models.dart';

final _log = Logger('space');

/// Perché una chiamata dello spazio non è riuscita (spec U §7.4).
enum SpaceFailure {
  /// 400, o risposta di forma inattesa.
  invalid,

  /// 404 di `start`: il titolo non c'è più nell'ultimo calcolo.
  unknown,

  /// 409 `Busy`: un'altra operazione sullo stesso titolo.
  busy,

  /// 409 `NotReady`: manca un calcolo recente.
  notReady,

  /// 404 di `operation` o `dropPending`.
  notFound,

  /// 401, 403: non ammesso.
  forbidden,

  /// Rete o timeout.
  network,

  /// Errore del server (anche 503).
  server,
}

class SpaceException implements Exception {
  const SpaceException(this.failure, [this.reason]);

  final SpaceFailure failure;

  /// Il `Reason` della risposta d'errore, se c'era (es. `NoFiles` per 502).
  final String? reason;

  @override
  String toString() => 'SpaceException(${failure.name})';
}

/// Endpoint dello spazio del plugin (spec U §7.4, solo admin).
/// Lancia solo [SpaceException].
class SpaceApi {
  SpaceApi(this._http);

  static const _base = '/WonderFlixWatchParty/Space';

  /// Esiti previsti: nel log come info, non tra gli "Ultimi errori".
  static const _quiet = {400, 403, 404, 409, 503};

  final JellyfinHttp _http;

  Future<SpaceOverview> overview() => _call(
    () async =>
        SpaceOverview.fromJson(await _http.get(_base, quietStatuses: _quiet)) ??
        (throw const ServerErrorException(null)),
  );

  Future<void> recalculate() =>
      _call(() => _http.post('$_base/Recalculate', quietStatuses: _quiet));

  /// Mette in coda l'operazione e dà il suo id.
  Future<String> start(String kind, String key) => _call(() async {
    final body = await _http.post(
      '$_base/Operations',
      body: {'Kind': kind, 'Key': key},
      quietStatuses: _quiet,
    );
    final id = body is Map ? body['Id'] : null;
    return id is String ? id : throw const ServerErrorException(null);
  }, notFound: SpaceFailure.unknown);

  Future<SpaceOperation> operation(String id) => _call(
    () async =>
        SpaceOperation.fromJson(
          await _http.get(
            '$_base/Operations/${Uri.encodeComponent(id)}',
            quietStatuses: _quiet,
          ),
        ) ??
        (throw const ServerErrorException(null)),
  );

  Future<void> keep(String key, String title) => _call(
    () => _http.post(
      '$_base/Kept',
      body: {'Key': key, 'Title': title},
      quietStatuses: _quiet,
    ),
  );

  Future<void> unkeep(String key) => _call(
    () =>
        _http.delete('$_base/Kept', query: {'key': key}, quietStatuses: _quiet),
  );

  /// Import a mano del download bloccato di una riga di Alleggerire; 404
  /// (niente più da importare) vale [SpaceFailure.unknown].
  Future<void> importLighten(String key) => _call(
    () => _http.post(
      '$_base/Lighten/Import',
      body: {'Key': key},
      quietStatuses: _quiet,
    ),
    notFound: SpaceFailure.unknown,
  );

  Future<void> dropPending(String hash) => _call(
    () => _http.delete(
      '$_base/Pending/${Uri.encodeComponent(hash)}',
      quietStatuses: _quiet,
    ),
  );

  Future<T> _call<T>(
    Future<T> Function() request, {
    SpaceFailure notFound = SpaceFailure.notFound,
  }) async {
    try {
      return await request();
    } on NotFoundException {
      throw SpaceException(notFound);
    } on UnauthorizedException {
      throw const SpaceException(SpaceFailure.forbidden);
    } on ForbiddenException {
      throw const SpaceException(SpaceFailure.forbidden);
    } on ServerErrorException catch (error) {
      final reason = error.body is Map ? (error.body as Map)['Reason'] : null;
      throw SpaceException(switch (error.statusCode) {
        400 => SpaceFailure.invalid,
        409 when reason == 'Busy' => SpaceFailure.busy,
        409 when reason == 'NotReady' => SpaceFailure.notReady,
        // Risposta 200 di forma inattesa.
        null => SpaceFailure.invalid,
        _ => SpaceFailure.server,
      }, reason is String ? reason : null);
    } on ApiException {
      throw const SpaceException(SpaceFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta dello spazio non valida: ${error.runtimeType}');
      throw const SpaceException(SpaceFailure.network);
    }
  }
}
