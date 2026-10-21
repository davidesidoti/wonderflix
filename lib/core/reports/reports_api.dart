import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'report_models.dart';

final _log = Logger('reports');

/// Perché una chiamata delle segnalazioni non è riuscita (spec R §6.2).
enum ReportsFailure {
  /// 404: plugin assente o vecchio (il plugin non risponde mai 404).
  unavailable,

  /// 400, o un 409 con un motivo che non conosciamo.
  invalid,

  /// 401, 403: non ammesso.
  forbidden,

  /// 409 `LimitReached`: troppe segnalazioni aperte.
  limitReached,

  /// 409 `Closed`: la segnalazione è già chiusa.
  closed,

  /// Rete, errore del server o risposta di forma inattesa.
  network,
}

class ReportsException implements Exception {
  const ReportsException(this.failure);

  final ReportsFailure failure;

  @override
  String toString() => 'ReportsException(${failure.name})';
}

/// Endpoint delle segnalazioni del plugin (spec R §6.2). Lancia solo
/// [ReportsException].
class ReportsApi {
  ReportsApi(this._http);

  static const _base = '/WonderFlixWatchParty/Reports';

  /// Esiti previsti (permesso, titolo sparito, limite o già chiusa): nel log
  /// come info, non tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {400, 403, 404, 409};

  final JellyfinHttp _http;

  /// Segnala un problema; una nota vuota non si manda.
  Future<ItemReport> create(
          {required String itemId,
          required ReportType type,
          String? note}) =>
      _call(() async {
        final data = await _http.post(_base,
            body: {
              'ItemId': itemId,
              'Type': type.wire,
              if (note != null && note.isNotEmpty) 'Note': note,
            },
            quietStatuses: _quiet);
        return ItemReport.fromJson(asJsonMap(data)) ??
            (throw const ServerErrorException(null));
      });

  /// Le segnalazioni aperte di chi chiama su un titolo.
  Future<List<ItemReport>> mine(String itemId) => _call(() async =>
      ItemReport.listFromJson(await _http.get('$_base/Mine',
          query: {'itemId': itemId}, quietStatuses: _quiet)));

  /// Tutte le segnalazioni aperte (solo admin).
  Future<List<ItemReport>> all() => _call(() async =>
      ItemReport.listFromJson(await _http.get(_base, quietStatuses: _quiet)));

  /// Chiude una segnalazione (solo admin); una nota vuota non si manda.
  Future<void> resolve(String reportId, ReportOutcome outcome,
          {String? note}) =>
      _call(() => _http.post('$_base/$reportId/Resolve',
          body: {
            'Outcome': outcome.wire,
            if (note != null && note.isNotEmpty) 'Note': note,
          },
          quietStatuses: _quiet));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const ReportsException(ReportsFailure.unavailable);
    } on UnauthorizedException {
      throw const ReportsException(ReportsFailure.forbidden);
    } on ForbiddenException {
      throw const ReportsException(ReportsFailure.forbidden);
    } on ServerErrorException catch (error) {
      throw ReportsException(switch (error.statusCode) {
        400 => ReportsFailure.invalid,
        409 => _reason(error.body),
        _ => ReportsFailure.network,
      });
    } on ApiException {
      throw const ReportsException(ReportsFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta delle segnalazioni non valida: ${error.runtimeType}');
      throw const ReportsException(ReportsFailure.network);
    }
  }

  static ReportsFailure _reason(Object? body) =>
      switch (body is Map ? body['Reason'] : null) {
        'LimitReached' => ReportsFailure.limitReached,
        'Closed' => ReportsFailure.closed,
        _ => ReportsFailure.invalid,
      };
}
