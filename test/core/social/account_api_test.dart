import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late AccountApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = AccountApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Matcher fails(AccountFailure failure) => throwsA(isA<AccountException>()
      .having((e) => e.failure, 'failure', failure));

  test('contatti: canali del server e contatti verificati', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Channels': {'Discord': true, 'Email': false},
          'Discord': {
            'Name': 'garg',
            'VerifiedAt': '2026-10-09T10:00:00+00:00',
          },
          'Email': null,
        });

    final contacts = await api.contacts();

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Account/Contacts');
    expect(contacts.isAvailable(AccountChannel.discord), isTrue);
    expect(contacts.isAvailable(AccountChannel.email), isFalse);
    expect(contacts.contactOf(AccountChannel.discord), 'garg');
    expect(contacts.contactOf(AccountChannel.email), isNull);
  });

  test('collegamento: Start con destinatario, password e lingua', () async {
    adapter.handler = (_) =>
        const FakeResponse(202, {'ExpiresAt': '2026-10-09T10:10:00+00:00'});

    await api.startLink(AccountChannel.email,
        target: 'a@example.com', password: 'vecchia', language: 'it');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path,
        '/WonderFlixWatchParty/Account/Contacts/Email/Start');
    expect(request.data,
        {'Target': 'a@example.com', 'Password': 'vecchia', 'Language': 'it'});
  });

  test('collegamento: Confirm manda il codice come stringa', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Channels': {'Discord': true, 'Email': true},
          'Email': {
            'Address': 'a@example.com',
            'VerifiedAt': '2026-10-09T10:00:00+00:00',
          },
        });

    final contacts = await api.confirmLink(AccountChannel.email, '012345');

    final request = adapter.requests.single;
    expect(request.path,
        '/WonderFlixWatchParty/Account/Contacts/Email/Confirm');
    // Una stringa: lo zero iniziale conta, e con un numero il plugin
    // risponderebbe 400 senza Code (spec L §7.6).
    expect(request.data, {'Code': '012345'});
    expect(contacts.contactOf(AccountChannel.email), 'a@example.com');
  });

  test('scollegamento: POST con la password, anche vuota', () async {
    await api.unlink(AccountChannel.discord, password: '');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path,
        '/WonderFlixWatchParty/Account/Contacts/Discord/Unlink');
    expect(request.data, {'Password': ''});
  });

  test('recupero: Start e Complete', () async {
    adapter.handler = (options) =>
        FakeResponse(options.path.endsWith('/Start') ? 202 : 204);

    await api.startRecovery(username: 'garg', language: 'en');
    await api.completeRecovery(
        username: 'garg',
        code: '000123',
        newPassword: 'nuova123',
        language: 'en');

    expect(adapter.requests[0].path,
        '/WonderFlixWatchParty/Account/Recovery/Start');
    expect(adapter.requests[0].data, {'Username': 'garg', 'Language': 'en'});
    expect(adapter.requests[1].path,
        '/WonderFlixWatchParty/Account/Recovery/Complete');
    expect(adapter.requests[1].data, {
      'Username': 'garg',
      'Code': '000123',
      'NewPassword': 'nuova123',
      'Language': 'en',
    });
  });

  test('errori: i Code del plugin e gli altri stati', () async {
    final cases = <(int, Object?, AccountFailure)>[
      (404, null, AccountFailure.unavailable),
      (503, {'Code': 'ChannelOff'}, AccountFailure.channelOff),
      (400, {'Code': 'InvalidTarget'}, AccountFailure.invalidTarget),
      (400, {'Code': 'MemberNotFound'}, AccountFailure.memberNotFound),
      (403, {'Code': 'WrongPassword'}, AccountFailure.wrongPassword),
      (409, {'Code': 'DmClosed'}, AccountFailure.dmClosed),
      (502, {'Code': 'SendFailed'}, AccountFailure.sendFailed),
      (400, {'Code': 'InvalidCode'}, AccountFailure.invalidCode),
      (400, {'Code': 'WeakPassword'}, AccountFailure.weakPassword),
      (429, {'Code': 'RateLimited'}, AccountFailure.rateLimited),
      (429, null, AccountFailure.rateLimited),
      (400, {'Code': 'Invalid'}, AccountFailure.invalid),
      (403, {'Code': 'NotAllowed'}, AccountFailure.invalid),
      // Il 400 di ASP.NET per un JSON rotto: niente Code.
      (400, {'title': 'One or more validation errors occurred.'},
          AccountFailure.invalid),
      (401, null, AccountFailure.invalid),
      // Recovery/Complete dopo un errore di Jellyfin: il codice è già usato.
      (500, null, AccountFailure.serverError),
      // nginx mentre Jellyfin si riavvia: senza il Code non è il plugin.
      (502, null, AccountFailure.network),
      (503, null, AccountFailure.network),
    ];
    for (final (status, body, failure) in cases) {
      adapter.handler = (_) => FakeResponse(status, body);
      await expectLater(api.unlink(AccountChannel.email, password: 'x'),
          fails(failure),
          reason: '$status $body');
    }
  });

  test('rete assente e risposta di forma inattesa', () async {
    adapter.handler = (_) => throw const SocketException('giù');
    await expectLater(api.contacts(), fails(AccountFailure.network));

    adapter.handler = (_) => const FakeResponse(200, ['non una mappa']);
    await expectLater(api.contacts(), fails(AccountFailure.network));

    adapter.handler = (_) => const FakeResponse(200, {'Channels': 'no'});
    await expectLater(api.contacts(), fails(AccountFailure.network));
  });

  test('esiti previsti nel log come info, il resto come avviso', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    for (final status in [400, 403, 404, 409, 429, 502, 503, 500]) {
      adapter.handler = (_) => FakeResponse(status);
      await expectLater(api.contacts(), throwsA(isA<AccountException>()));
    }

    expect([
      for (final record in records)
        if (record.loggerName == 'http') record.level,
    ], [...List.filled(7, Level.INFO), Level.WARNING]);
  });
}
