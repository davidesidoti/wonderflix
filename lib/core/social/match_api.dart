import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'match_models.dart';

final _log = Logger('match');

/// Perché una chiamata del match non è riuscita (spec P §6.4).
enum MatchFailure {
  /// 404: plugin assente o senza il match (il plugin non risponde mai 404).
  unavailable,

  /// 400, 401, 403: richiesta non valida o non ammessa.
  invalid,

  /// 429: troppi voti o inviti in poco tempo.
  rateLimited,

  // I motivi dei 409 (`{Reason}`).
  inAnotherRoom,
  notMember,
  notCreator,
  started,
  closed,
  full,
  notInvited,
  notEnoughMembers,
  notStarted,
  notNext,
  notFinished,
  notYourParty,

  /// Un 409 con un motivo che non conosciamo.
  conflict,

  /// Rete, errore del server o risposta di forma inattesa.
  network,
}

class MatchException implements Exception {
  const MatchException(this.failure, {this.roomId});

  final MatchFailure failure;

  /// Con [MatchFailure.inAnotherRoom]: la sala in cui il plugin ci vede già
  /// (piano 22a), per uscirne o rientrarci.
  final String? roomId;

  @override
  String toString() => 'MatchException(${failure.name})';
}

/// Endpoint del match del plugin (spec P §6.4). Lancia solo [MatchException].
class MatchApi {
  MatchApi(this._http);

  static const _base = '/WonderFlixWatchParty/Match';

  /// Esiti previsti (sala chiusa, già in una sala, voto fuori ordine, troppi
  /// voti): nel log come info, non tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {403, 404, 409, 429};

  final JellyfinHttp _http;

  /// Apre una sala nuova; chi chiama ne è l'unico membro.
  Future<MatchState> open() =>
      _call(() async => _state(await _http.post(_base, quietStatuses: _quiet)));

  /// Lo stato della sala, per i membri.
  Future<MatchState> state(String roomId) => _call(() async =>
      _state(await _http.get('$_base/$roomId', quietStatuses: _quiet)));

  /// Invita amici (solo chi ha aperto, in attesa).
  Future<void> invite(String roomId, List<String> userIds) => _call(() =>
      _http.post('$_base/$roomId/Invites',
          body: {'UserIds': userIds}, quietStatuses: _quiet));

  /// Entra su invito; per chi è già dentro, lo stato.
  Future<MatchState> join(String roomId) => _call(() async => _state(
      await _http.post('$_base/$roomId/Join', quietStatuses: _quiet)));

  /// Esce; il plugin risponde 204 anche se non eravamo nella sala.
  Future<void> leave(String roomId) => _call(
      () => _http.post('$_base/$roomId/Leave', quietStatuses: _quiet));

  /// "Inizia" con i filtri, nei valori di "Cosa guardo stasera?".
  Future<MatchState> start(String roomId,
          {required String type,
          required String duration,
          String? genre,
          required String rating}) =>
      _call(() async => _state(await _http.post('$_base/$roomId/Start',
          body: {
            'Type': type,
            'Duration': duration,
            'Genre': genre,
            'Rating': rating
          },
          quietStatuses: _quiet)));

  /// Il voto per il prossimo titolo della pila.
  Future<void> vote(String roomId, String itemId, {required bool yes}) =>
      _call(() => _http.post('$_base/$roomId/Votes',
          body: {'ItemId': itemId, 'Yes': yes}, quietStatuses: _quiet));

  /// "Altri 30", quando tutti hanno finito.
  Future<MatchState> more(String roomId) => _call(() async => _state(
      await _http.post('$_base/$roomId/More', quietStatuses: _quiet)));

  /// Il party privato avviato da chi ha aperto: i membri ci entrano.
  Future<void> party(String roomId, String groupId) => _call(() =>
      _http.post('$_base/$roomId/Party',
          body: {'GroupId': groupId}, quietStatuses: _quiet));

  static MatchState _state(Object? data) => MatchState.fromJson(asJsonMap(data));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const MatchException(MatchFailure.unavailable);
    } on UnauthorizedException {
      throw const MatchException(MatchFailure.invalid);
    } on ForbiddenException {
      throw const MatchException(MatchFailure.invalid);
    } on ServerErrorException catch (error) {
      if (error.statusCode == 409) {
        throw MatchException(_reason(error.body), roomId: _roomId(error.body));
      }
      throw MatchException(switch (error.statusCode) {
        400 => MatchFailure.invalid,
        429 => MatchFailure.rateLimited,
        _ => MatchFailure.network,
      });
    } on ApiException {
      throw const MatchException(MatchFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta del match non valida: ${error.runtimeType}');
      throw const MatchException(MatchFailure.network);
    }
  }

  static MatchFailure _reason(Object? body) =>
      switch (body is Map ? body['Reason'] : null) {
        'InAnotherRoom' => MatchFailure.inAnotherRoom,
        'NotMember' => MatchFailure.notMember,
        'NotCreator' => MatchFailure.notCreator,
        'Started' => MatchFailure.started,
        'Closed' => MatchFailure.closed,
        'Full' => MatchFailure.full,
        'NotInvited' => MatchFailure.notInvited,
        'NotEnoughMembers' => MatchFailure.notEnoughMembers,
        'NotStarted' => MatchFailure.notStarted,
        'NotNext' => MatchFailure.notNext,
        'NotFinished' => MatchFailure.notFinished,
        'NotYourParty' => MatchFailure.notYourParty,
        _ => MatchFailure.conflict,
      };

  static String? _roomId(Object? body) {
    if (body is! Map) return null;
    final id = body['RoomId'];
    return id is String ? id : null;
  }
}
