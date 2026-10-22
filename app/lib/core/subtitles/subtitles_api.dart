import 'dart:convert';

import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'subtitle_models.dart';

final _log = Logger('subtitles');

/// Perché una chiamata dei sottotitoli non è riuscita (spec R §6.4).
enum SubtitlesFailure {
  /// 404: plugin assente o vecchio, o titolo sparito.
  unavailable,

  /// 401, 403: non ammesso.
  forbidden,

  /// 400: richiesta non valida.
  invalid,

  /// 502: il provider o Jellyfin non ce l'hanno fatta.
  failed,

  /// Rete, errore del server o risposta di forma inattesa.
  network,
}

class SubtitlesException implements Exception {
  const SubtitlesException(this.failure);

  final SubtitlesFailure failure;

  @override
  String toString() => 'SubtitlesException(${failure.name})';
}

/// Endpoint dei sottotitoli: ricerca, scarico e caricamento dal plugin,
/// eliminazione da Jellyfin (spec R §6.4). Lancia solo [SubtitlesException].
class SubtitlesApi {
  SubtitlesApi(this._http);

  static const _base = '/WonderFlixWatchParty/Subtitles';

  /// Esiti previsti (permesso tolto, provider che non risponde): nel log come
  /// info, non tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {400, 403, 404, 502};

  final JellyfinHttp _http;

  /// Cerca nei provider; [perfectMatch] limita ai sincronizzati col file.
  Future<List<RemoteSubtitle>> search(String itemId, String language,
          {bool? perfectMatch}) =>
      _call(() async {
        final data = await _http.get('$_base/$itemId/Search',
            query: {'language': language, 'perfectMatch': ?perfectMatch},
            quietStatuses: _quiet);
        if (data is! List) throw const ServerErrorException(null);
        return [
          for (final item in data)
            if (item is Map) RemoteSubtitle.fromJson(item),
        ];
      });

  /// Chiede al server di scaricare un risultato; la traccia compare dopo il
  /// refresh del plugin.
  Future<void> download(String itemId, String subtitleId) => _call(() =>
      _http.post('$_base/$itemId/Download',
          body: {'SubtitleId': subtitleId}, quietStatuses: _quiet));

  /// Carica un file dell'utente.
  Future<void> upload(String itemId, SubtitleUpload upload) =>
      _call(() => _http.post('$_base/$itemId/Upload',
          body: {
            'Language': upload.language,
            'Format': upload.format,
            'IsForced': upload.isForced,
            'IsHearingImpaired': upload.isHearingImpaired,
            'Data': base64Encode(upload.bytes),
          },
          quietStatuses: _quiet));

  /// Elimina una traccia esterna (solo admin, Jellyfin).
  Future<void> delete(String itemId, int streamIndex) => _call(() => _http
      .delete('/Videos/$itemId/Subtitles/$streamIndex', quietStatuses: _quiet));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const SubtitlesException(SubtitlesFailure.unavailable);
    } on UnauthorizedException {
      throw const SubtitlesException(SubtitlesFailure.forbidden);
    } on ForbiddenException {
      throw const SubtitlesException(SubtitlesFailure.forbidden);
    } on ServerErrorException catch (error) {
      throw SubtitlesException(switch (error.statusCode) {
        400 => SubtitlesFailure.invalid,
        502 => SubtitlesFailure.failed,
        _ => SubtitlesFailure.network,
      });
    } on ApiException {
      throw const SubtitlesException(SubtitlesFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta dei sottotitoli non valida: ${error.runtimeType}');
      throw const SubtitlesException(SubtitlesFailure.network);
    }
  }
}
