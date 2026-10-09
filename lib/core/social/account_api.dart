import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'account_models.dart';

final _log = Logger('account');

/// Perché una chiamata dell'account non è riuscita (spec L §7.6).
enum AccountFailure {
  /// 404: plugin assente o vecchio (il plugin non risponde mai 404 di suo).
  unavailable,

  /// 503 `ChannelOff`: il canale non è configurato sul server.
  channelOff,

  /// 400 `InvalidTarget`: non sembra un nome utente Discord o un'email.
  invalidTarget,

  /// 400 `MemberNotFound`: nessun membro del server Discord con quel nome.
  memberNotFound,

  /// 403 `WrongPassword`: la password attuale è sbagliata. Non è un 401: la
  /// sessione resta aperta.
  wrongPassword,

  /// 409 `DmClosed`: il bot non può scrivere all'utente.
  dmClosed,

  /// 502 `SendFailed`: Discord o il server di posta non hanno preso il
  /// messaggio.
  sendFailed,

  /// 400 `InvalidCode`: codice sbagliato, scaduto o già usato.
  invalidCode,

  /// 400 `WeakPassword`: la password nuova è fuori dai limiti.
  weakPassword,

  /// 429: troppe richieste o troppi tentativi.
  rateLimited,

  /// Un altro 400, 401, 403 o 409, anche senza `Code` (`Invalid`,
  /// `NotAllowed`, il 400 di ASP.NET per un JSON rotto).
  invalid,

  /// Rete, errore del server (anche il 500 di `Recovery/Complete`) o
  /// risposta di forma inattesa.
  network,
}

class AccountException implements Exception {
  const AccountException(this.failure);

  final AccountFailure failure;

  @override
  String toString() => 'AccountException(${failure.name})';
}

/// Contatti per il recupero e recupero della password, nel plugin (spec L
/// §7.6). Lancia solo [AccountException]. Le chiamate di `Recovery/*` non
/// vogliono un token: nell'accesso il client non ne ha.
class AccountApi {
  AccountApi(this._http);

  static const _base = '/WonderFlixWatchParty/Account';

  /// Esiti previsti (password sbagliata, codice scaduto, limiti, canale
  /// spento, invio non riuscito, plugin vecchio): nel log come info, non
  /// tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {400, 403, 404, 409, 429, 502, 503};

  final JellyfinHttp _http;

  /// I canali del server e i contatti verificati dell'utente.
  Future<AccountContacts> contacts() => _call(() async =>
      AccountContacts.fromJson(asJsonMap(
          await _http.get('$_base/Contacts', quietStatuses: _quiet))));

  /// Manda il codice a [target] (nome utente Discord o email) per
  /// collegarlo. [password] è la password attuale dell'account, vuota se
  /// non ne ha una.
  Future<void> startLink(AccountChannel channel,
          {required String target,
          required String password,
          required String language}) =>
      _call(() => _http.post('$_base/Contacts/${channel.wire}/Start',
          body: {'Target': target, 'Password': password, 'Language': language},
          quietStatuses: _quiet));

  /// Conferma il collegamento con il codice ricevuto: i contatti di adesso.
  /// Il codice va come stringa (lo zero iniziale conta).
  Future<AccountContacts> confirmLink(AccountChannel channel, String code) =>
      _call(() async => AccountContacts.fromJson(asJsonMap(await _http.post(
          '$_base/Contacts/${channel.wire}/Confirm',
          body: {'Code': code},
          quietStatuses: _quiet))));

  /// Scollega il contatto di [channel] (204 anche se non c'era). È un
  /// `POST`: la password non deve stare nell'indirizzo.
  Future<void> unlink(AccountChannel channel, {required String password}) =>
      _call(() => _http.post('$_base/Contacts/${channel.wire}/Unlink',
          body: {'Password': password}, quietStatuses: _quiet));

  /// Chiede il codice di recupero per [username]. Il plugin risponde 202
  /// che l'account esista o no.
  Future<void> startRecovery(
          {required String username, required String language}) =>
      _call(() => _http.post('$_base/Recovery/Start',
          body: {'Username': username, 'Language': language},
          quietStatuses: _quiet));

  /// Cambia la password con il codice di recupero. [language] è la lingua
  /// dell'avviso "password cambiata".
  Future<void> completeRecovery(
          {required String username,
          required String code,
          required String newPassword,
          required String language}) =>
      _call(() => _http.post('$_base/Recovery/Complete',
          body: {
            'Username': username,
            'Code': code,
            'NewPassword': newPassword,
            'Language': language,
          },
          quietStatuses: _quiet));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const AccountException(AccountFailure.unavailable);
    } on UnauthorizedException {
      throw const AccountException(AccountFailure.invalid);
    } on ForbiddenException catch (error) {
      throw AccountException(_code(error.body) == 'WrongPassword'
          ? AccountFailure.wrongPassword
          : AccountFailure.invalid);
    } on ServerErrorException catch (error) {
      throw AccountException(switch ((error.statusCode, _code(error.body))) {
        (400, 'InvalidTarget') => AccountFailure.invalidTarget,
        (400, 'MemberNotFound') => AccountFailure.memberNotFound,
        (400, 'InvalidCode') => AccountFailure.invalidCode,
        (400, 'WeakPassword') => AccountFailure.weakPassword,
        (409, 'DmClosed') => AccountFailure.dmClosed,
        (400 || 409, _) => AccountFailure.invalid,
        (429, _) => AccountFailure.rateLimited,
        (502, 'SendFailed') => AccountFailure.sendFailed,
        (503, 'ChannelOff') => AccountFailure.channelOff,
        _ => AccountFailure.network,
      });
    } on ApiException {
      throw const AccountException(AccountFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta dell\'account non valida: ${error.runtimeType}');
      throw const AccountException(AccountFailure.network);
    }
  }

  static String? _code(Object? body) {
    if (body is! Map) return null;
    final code = body['Code'];
    return code is String ? code : null;
  }
}
