import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'party_channel_models.dart';

final _log = Logger('watchparty');

/// Perché una chiamata al plugin non è riuscita (spec E §6.2).
enum PartyChannelFailure {
  /// 404: la rotta non esiste, cioè il plugin non è installato (il plugin
  /// non risponde mai 404 di suo).
  unavailable,

  /// 429: troppi eventi in poco tempo.
  rateLimited,

  /// 400, 401, 403: evento non valido, o non siamo nel gruppo.
  rejected,

  /// 409: il plugin non trova la nostra sessione.
  sessionUnknown,

  /// Rete assente, errore del server o risposta di forma inattesa.
  network,
}

class PartyChannelException implements Exception {
  const PartyChannelException(this.failure);

  final PartyChannelFailure failure;

  @override
  String toString() => 'PartyChannelException(${failure.name})';
}

/// Endpoint del plugin "WonderFlix Watch Party" (spec E §6.2). Lancia solo
/// [PartyChannelException].
class PartyChannelApi {
  PartyChannelApi(this._http);

  static const _base = '/WonderFlixWatchParty';

  final JellyfinHttp _http;

  Future<PartyPluginInfo> info() => _call(() async =>
      PartyPluginInfo.fromJson(asJsonMap(await _http.get('$_base/Info'))));

  /// Registra la nostra sessione nel gruppo; restituisce lo storico della
  /// chat, dal messaggio più vecchio.
  Future<List<PartyChatEvent>> join(String groupId) => _call(() async {
        final json =
            asJsonMap(await _http.post('$_base/Groups/$groupId/Join'));
        return [
          for (final raw in json['Messages'] as List? ?? const [])
            if (parsePartyEvent(raw) case final PartyChatEvent event) event,
        ];
      });

  Future<void> leave(String groupId) =>
      _call(() => _http.post('$_base/Groups/$groupId/Leave'));

  /// Manda [event] al gruppo; restituisce l'evento timbrato dal plugin.
  Future<PartyEvent> send(String groupId, PartyOutgoing event) =>
      _call(() async {
        final stamped = parsePartyEvent(await _http
            .post('$_base/Groups/$groupId/Events', body: event.toJson()));
        if (stamped == null) throw const ServerErrorException(null);
        return stamped;
      });

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const PartyChannelException(PartyChannelFailure.unavailable);
    } on UnauthorizedException {
      throw const PartyChannelException(PartyChannelFailure.rejected);
    } on ForbiddenException {
      throw const PartyChannelException(PartyChannelFailure.rejected);
    } on ServerErrorException catch (error) {
      throw PartyChannelException(switch (error.statusCode) {
        400 => PartyChannelFailure.rejected,
        409 => PartyChannelFailure.sessionUnknown,
        429 => PartyChannelFailure.rateLimited,
        _ => PartyChannelFailure.network,
      });
    } on ApiException {
      throw const PartyChannelException(PartyChannelFailure.network);
    } on Object catch (error) {
      // Risposta di forma inattesa (es. `Info` senza `Protocol`).
      _log.info('risposta del plugin del watch party non valida: $error');
      throw const PartyChannelException(PartyChannelFailure.network);
    }
  }
}
