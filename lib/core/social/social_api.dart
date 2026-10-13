import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import '../jellyfin/json_fields.dart';
import '../syncplay/syncplay_models.dart';
import 'inbox_models.dart';
import 'recommendation_models.dart';
import 'social_models.dart';

final _log = Logger('social');

/// Perché una chiamata sociale al plugin non è riuscita (spec F §6.7).
enum SocialFailure {
  /// 404: la rotta non esiste, cioè plugin assente o vecchio (il plugin non
  /// risponde mai 404 di suo).
  unavailable,

  /// 400, 401, 403: non ammessa (es. una richiesta che non c'è più).
  forbidden,

  /// 409: non ammessa adesso (già amici, richiesta doppia, limiti).
  conflict,

  /// 429: troppe richieste in poco tempo.
  rateLimited,

  /// Rete assente, errore del server o risposta di forma inattesa.
  network,
}

class SocialException implements Exception {
  const SocialException(this.failure);

  final SocialFailure failure;

  @override
  String toString() => 'SocialException(${failure.name})';
}

/// Endpoint sociali del plugin "WonderFlix Watch Party" (spec F §6.7).
/// Lancia solo [SocialException].
class SocialApi {
  SocialApi(this._http);

  static const _base = '/WonderFlixWatchParty';

  /// Esiti previsti (plugin assente, già amici, troppe richieste, richiesta
  /// non più valida: accettare o rifiutare una richiesta già annullata è una
  /// corsa normale, 403): nel log come info, non tra gli "Ultimi errori"
  /// della diagnostica.
  static const _quiet = {403, 404, 409, 429};

  final JellyfinHttp _http;

  Future<SocialPluginInfo> info() => _call(() async => SocialPluginInfo
      .fromJson(asJsonMap(await _http.get('$_base/Info', quietStatuses: _quiet))));

  Future<FriendsSnapshot> friends() => _call(() async => FriendsSnapshot
      .fromJson(asJsonMap(await _http.get('$_base/Friends', quietStatuses: _quiet))));

  /// Utenti il cui nome contiene [query] (il plugin vuole almeno 2 lettere).
  Future<List<UserSearchResult>> search(String query) => _call(() async {
        final json = await _http.get('$_base/Users/Search',
            query: {'q': query}, quietStatuses: _quiet);
        return [
          for (final raw in json as List)
            UserSearchResult.fromJson(raw as Map<String, dynamic>),
        ];
      });

  Future<void> request(String userId) => _call(() => _http
      .post('$_base/Friends/Requests/$userId', quietStatuses: _quiet));

  Future<void> accept(String userId) => _call(() => _http.post(
      '$_base/Friends/Requests/$userId/Accept',
      quietStatuses: _quiet));

  Future<void> decline(String userId) => _call(() => _http.post(
      '$_base/Friends/Requests/$userId/Decline',
      quietStatuses: _quiet));

  /// Annulla la nostra richiesta a [userId].
  Future<void> cancel(String userId) => _call(() => _http
      .delete('$_base/Friends/Requests/$userId', quietStatuses: _quiet));

  Future<void> remove(String userId) => _call(
      () => _http.delete('$_base/Friends/$userId', quietStatuses: _quiet));

  /// Registra il party appena creato (spec F §6.4): il codice per un
  /// privato, altrimenti `null`.
  Future<String?> registerParty(String groupId, PartyMode mode) =>
      _call(() async {
        final json = asJsonMap(await _http.post('$_base/Parties/$groupId',
            body: {'Mode': mode.wire}, quietStatuses: _quiet));
        return json['Code'] as String?;
      });

  /// I party che possiamo vedere, già filtrati dal plugin.
  Future<List<GroupInfo>> parties() => _call(() async {
        final json = await _http.get('$_base/Parties', quietStatuses: _quiet);
        return [
          for (final raw in json as List)
            partyGroupFromJson(raw as Map<String, dynamic>),
        ];
      });

  /// Modalità e codice del party in cui siamo.
  Future<PartyDetails> partyDetails(String groupId) => _call(() async =>
      PartyDetails.fromJson(asJsonMap(await _http
          .get('$_base/Parties/$groupId', quietStatuses: _quiet))));

  /// Il gruppo di un codice (già in forma canonica).
  Future<String> joinByCode(String code) => _call(() async =>
      asJsonMap(await _http.post('$_base/Parties/Join',
          body: {'Code': code}, quietStatuses: _quiet))['GroupId'] as String);

  /// Invita amici nel party (solo i nostri amici fuori dal gruppo).
  Future<void> invite(String groupId, List<String> userIds) => _call(() =>
      _http.post('$_base/Parties/$groupId/Invites',
          body: {'UserIds': userIds}, quietStatuses: _quiet));

  /// La cassetta delle notifiche (spec G §6.3).
  Future<InboxSnapshot> inbox() => _call(() async => InboxSnapshot.fromJson(
      asJsonMap(await _http.get('$_base/Inbox', quietStatuses: _quiet))));

  /// Segna lette le voci fino a [upTo] (il Seq della più recente vista).
  Future<void> markInboxRead(int upTo) => _call(() => _http.post(
      '$_base/Inbox/Read',
      body: {'UpTo': upTo},
      quietStatuses: _quiet));

  /// Toglie una voce (il plugin risponde 204 anche se non c'è più).
  Future<void> removeInboxEntry(String id) => _call(() =>
      _http.delete('$_base/Inbox/Entries/$id', quietStatuses: _quiet));

  /// Svuota la cassetta.
  Future<void> clearInbox() =>
      _call(() => _http.delete('$_base/Inbox', quietStatuses: _quiet));

  /// Gli amici a cui si può consigliare [itemId], con online e accesso al
  /// titolo (spec N §6.2).
  Future<List<RecommendationTarget>> recommendationTargets(String itemId) =>
      _call(() async => jsonList(
          asJsonMap(await _http.get('$_base/Recommendations/Targets',
              query: {'itemId': itemId}, quietStatuses: _quiet))['Friends'],
          RecommendationTarget.fromJson));

  /// Consiglia [itemId] agli amici [userIds]; risponde a quanti è arrivato.
  Future<int> recommend(String itemId, List<String> userIds, String? message) =>
      _call(() async => (asJsonMap(await _http.post('$_base/Recommendations',
              body: {'ItemId': itemId, 'To': userIds, 'Message': message},
              quietStatuses: _quiet))['Sent'] as num)
          .toInt());

  /// I consigli ricevuti ancora validi, dal più recente.
  Future<List<Recommendation>> recommendations() => _call(() async => jsonList(
      asJsonMap(await _http.get('$_base/Recommendations', quietStatuses: _quiet))[
          'Items'],
      Recommendation.fromJson));

  /// "Non mi interessa": il plugin risponde 204 anche se il titolo non c'è.
  Future<void> dismissRecommendation(String itemId) => _call(() =>
      _http.delete('$_base/Recommendations/$itemId', quietStatuses: _quiet));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const SocialException(SocialFailure.unavailable);
    } on UnauthorizedException {
      throw const SocialException(SocialFailure.forbidden);
    } on ForbiddenException {
      throw const SocialException(SocialFailure.forbidden);
    } on ServerErrorException catch (error) {
      throw SocialException(switch (error.statusCode) {
        400 => SocialFailure.forbidden,
        409 => SocialFailure.conflict,
        429 => SocialFailure.rateLimited,
        _ => SocialFailure.network,
      });
    } on ApiException {
      throw const SocialException(SocialFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta sociale del plugin non valida: ${error.runtimeType}');
      throw const SocialException(SocialFailure.network);
    }
  }
}
