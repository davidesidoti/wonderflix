import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/account_providers.dart';

/// `AccountApi` senza rete: registra le chiamate e risponde con i campi. Un
/// `…Failure` diverso da `null` fa lanciare quel metodo.
class FakeAccountApi implements AccountApi {
  AccountContacts contactsResult =
      const AccountContacts(discordAvailable: true, emailAvailable: true);
  AccountFailure? contactsFailure;
  int contactsCalls = 0;

  final startLinkCalls = <({
    AccountChannel channel,
    String target,
    String password,
    String language,
  })>[];
  AccountFailure? startLinkFailure;

  final confirmCalls = <(AccountChannel, String)>[];
  AccountFailure? confirmFailure;

  /// I contatti dati da [confirmLink]; `null`: [contactsResult].
  AccountContacts? confirmResult;

  final unlinkCalls = <(AccountChannel, String)>[];
  AccountFailure? unlinkFailure;

  final recoveryStarts = <(String, String)>[];
  AccountFailure? startRecoveryFailure;

  final recoveryCompletes = <({
    String username,
    String code,
    String newPassword,
    String language,
  })>[];
  AccountFailure? completeRecoveryFailure;

  /// Se c'è, ogni chiamata aspetta che si completi (lo stato "in corso").
  Completer<void>? gate;

  Future<void> _answer(AccountFailure? failure) async {
    await gate?.future;
    if (failure != null) throw AccountException(failure);
  }

  @override
  Future<AccountContacts> contacts() async {
    contactsCalls++;
    await _answer(contactsFailure);
    return contactsResult;
  }

  @override
  Future<void> startLink(AccountChannel channel,
      {required String target,
      required String password,
      required String language}) async {
    startLinkCalls.add((
      channel: channel,
      target: target,
      password: password,
      language: language,
    ));
    await _answer(startLinkFailure);
  }

  @override
  Future<AccountContacts> confirmLink(
      AccountChannel channel, String code) async {
    confirmCalls.add((channel, code));
    await _answer(confirmFailure);
    return confirmResult ?? contactsResult;
  }

  @override
  Future<void> unlink(AccountChannel channel,
      {required String password}) async {
    unlinkCalls.add((channel, password));
    await _answer(unlinkFailure);
  }

  @override
  Future<void> startRecovery(
      {required String username, required String language}) async {
    recoveryStarts.add((username, language));
    await _answer(startRecoveryFailure);
  }

  @override
  Future<void> completeRecovery(
      {required String username,
      required String code,
      required String newPassword,
      required String language}) async {
    recoveryCompletes.add((
      username: username,
      code: code,
      newPassword: newPassword,
      language: language,
    ));
    await _answer(completeRecoveryFailure);
  }
}

/// I provider dell'account in un widget test: [api] al posto del plugin e
/// la funzione `account` accesa o spenta, senza chiedere `Info`.
List<Override> accountTestOverrides(FakeAccountApi api,
        {bool available = true}) =>
    [
      accountApiProvider.overrideWithValue(api),
      accountAvailableProvider.overrideWithValue(available),
    ];
