import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/core/social/plugin_admin_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late PluginAdminApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = PluginAdminApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('utenti: contatti, email mascherata, ultimo promemoria', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {
            'Id': 'a1',
            'Name': 'garg',
            'IsAdmin': false,
            'Enabled': true,
            'Discord': {'Name': 'garg'},
            'Email': {'Masked': 'g•••@example.com'},
            'LastReminderAt': '2026-10-01T08:00:00+00:00',
          },
          {
            'Id': 'a2',
            'Name': 'Mario',
            'IsAdmin': true,
            'Enabled': true,
            'Discord': null,
            'Email': null,
            'LastReminderAt': null,
          },
        ]);

    final users = await api.accountUsers();

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Account/Admin/Users');
    expect(users.map((u) => u.name), ['garg', 'Mario']);
    expect(users[0].discordName, 'garg');
    expect(users[0].maskedEmail, 'g•••@example.com');
    expect(users[0].hasContacts, isTrue);
    expect(users[0].lastReminderAt, DateTime.utc(2026, 10, 1, 8));
    expect(users[1].isAdmin, isTrue);
    expect(users[1].hasContacts, isFalse);
  });

  test('utenti: senza Id, Name, IsAdmin o Enabled la risposta non vale',
      () async {
    const valid = {
      'Id': 'a1',
      'Name': 'garg',
      'IsAdmin': false,
      'Enabled': true,
    };
    // Con tutti e quattro i campi la risposta vale: la prova qui sotto
    // fallisce solo per il campo tolto.
    adapter.handler = (_) => const FakeResponse(200, [valid]);
    expect((await api.accountUsers()).single.name, 'garg');

    for (final missing in valid.keys) {
      final user = Map<String, Object?>.of(valid)..remove(missing);
      adapter.handler = (_) => FakeResponse(200, [user]);
      await expectLater(
          api.accountUsers(), throwsA(isA<ServerErrorException>()),
          reason: 'senza $missing');
    }

    adapter.handler = (_) => const FakeResponse(200, {'Users': []});
    await expectLater(
        api.accountUsers(), throwsA(isA<ServerErrorException>()));
  });

  test('codice di recupero: lingua nel corpo, i canali usati', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Channels': ['Discord', 'Email', 'Telegram'],
        });

    final channels = await api.sendRecoveryCode('a1', language: 'it');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path,
        '/WonderFlixWatchParty/Account/Admin/Users/a1/Recovery');
    expect(request.data, {'Language': 'it'});
    expect(channels, [AccountChannel.discord, AccountChannel.email]);
  });

  test('codice di recupero: un 200 senza un canale che conosciamo non vale',
      () async {
    // Un 200 del plugin ha sempre almeno un canale: zero (o solo canali che
    // l'app non conosce) è una risposta che non capiamo.
    for (final channels in [
      <String>[],
      ['Telegram'],
    ]) {
      adapter.handler = (_) => FakeResponse(200, {'Channels': channels});
      await expectLater(api.sendRecoveryCode('a1', language: 'it'),
          throwsA(isA<ServerErrorException>()),
          reason: '$channels');
    }

    adapter.handler = (_) => const FakeResponse(200, {'Other': 1});
    await expectLater(api.sendRecoveryCode('a1', language: 'it'),
        throwsA(isA<ServerErrorException>()));
  });

  test('scollegamento: DELETE dei contatti', () async {
    await api.unlinkContacts('a1');

    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Account/Admin/Users/a1/Contacts');
  });

  test('stato: canali, ultimo errore, conteggi, promemoria', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Discord': {
            'Configured': true,
            'LastError': {'At': '2026-10-09T08:00:00+00:00', 'Code': 'DmClosed'},
          },
          'Email': {'Configured': false, 'LastError': null},
          'WithContacts': 5,
          'Users': 23,
          'ReminderDays': 0,
        });

    final status = await api.accountStatus();

    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Account/Admin/Status');
    expect(status.discord.configured, isTrue);
    expect(status.discord.lastError!.code, 'DmClosed');
    expect(status.discord.lastError!.at, DateTime.utc(2026, 10, 9, 8));
    expect(status.channel(AccountChannel.email).configured, isFalse);
    expect(status.email.lastError, isNull);
    expect(status.withContacts, 5);
    expect(status.users, 23);
    expect(status.reminderDays, 0);
  });

  test('stato: i campi obbligatori ci devono essere', () async {
    const valid = {
      'Discord': {'Configured': true},
      'Email': {'Configured': false},
      'WithContacts': 5,
      'Users': 23,
      'ReminderDays': 14,
    };
    // Con tutti i campi la risposta vale: le prove sotto falliscono solo per
    // il campo tolto.
    adapter.handler = (_) => const FakeResponse(200, valid);
    expect((await api.accountStatus()).users, 23);

    for (final missing in valid.keys) {
      final status = Map<String, Object?>.of(valid)..remove(missing);
      adapter.handler = (_) => FakeResponse(200, status);
      await expectLater(
          api.accountStatus(), throwsA(isA<ServerErrorException>()),
          reason: 'senza $missing');
    }

    // Un ultimo errore senza l'ora (o senza il Code) non vale.
    for (final lastError in <Map<String, Object?>>[
      {'Code': 'DmClosed'},
      {'At': '2026-10-09T08:00:00+00:00'},
    ]) {
      final status = {
        ...valid,
        'Discord': {'Configured': true, 'LastError': lastError},
      };
      adapter.handler = (_) => FakeResponse(200, status);
      await expectLater(
          api.accountStatus(), throwsA(isA<ServerErrorException>()),
          reason: 'LastError $lastError');
    }
  });

  test('prova: solo la lingua nel corpo; un esito per canale', () async {
    adapter.handler =
        (_) => const FakeResponse(200, {'Discord': 'Ok', 'Email': 'NoContact'});

    final result = await api.testAccountChannels(language: 'en');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/WonderFlixWatchParty/Account/Admin/Test');
    // Senza Discord ed Email: la prova va ai contatti dell'admin (spec L
    // §9.6).
    expect(request.data, {'Language': 'en'});
    expect(result.of(AccountChannel.discord), 'Ok');
    expect(result.of(AccountChannel.email), 'NoContact');
  });

  test('errori del codice: il Code del plugin si legge, nel log come info',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    final cases = <(int, String)>[
      (403, 'NotAllowed'),
      (409, 'NoContacts'),
      (502, 'SendFailed'),
      (400, 'UnknownUser'),
    ];
    for (final (status, code) in cases) {
      adapter.handler = (_) => FakeResponse(status, {'Code': code});
      Object? caught;
      try {
        await api.sendRecoveryCode('a1', language: 'it');
      } on Object catch (error) {
        caught = error;
      }
      // `AdminTabController.act` dipende dal tipo: il 403 è una
      // `ForbiddenException`, gli altri errori del server hanno il loro
      // codice di stato.
      if (status == 403) {
        expect(caught, isA<ForbiddenException>(), reason: '$status');
      } else {
        expect(caught, isA<ServerErrorException>(), reason: '$status');
        expect((caught! as ServerErrorException).statusCode, status,
            reason: '$status');
      }
      expect(pluginErrorCode(caught!), code, reason: '$status');
    }
    expect([
      for (final record in records)
        if (record.loggerName == 'http') record.level,
    ], List.filled(cases.length, Level.INFO));
  });

  test('scollegamento: un 400 UnknownUser, il Code si legge e il log è info',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    adapter.handler = (_) => const FakeResponse(400, {'Code': 'UnknownUser'});

    Object? caught;
    try {
      await api.unlinkContacts('a1');
    } on Object catch (error) {
      caught = error;
    }

    expect(caught, isA<ServerErrorException>());
    expect((caught! as ServerErrorException).statusCode, 400);
    expect(pluginErrorCode(caught), 'UnknownUser');
    expect([
      for (final record in records)
        if (record.loggerName == 'http') record.level,
    ], [Level.INFO]);
  });

  test('pluginErrorCode: senza Code, o un errore che non viene dal server',
      () {
    expect(pluginErrorCode(const ForbiddenException()), isNull);
    expect(pluginErrorCode(const ServerErrorException(500, 'testo')), isNull);
    expect(pluginErrorCode(const ServerErrorException(409, {'Code': 3})),
        isNull);
    expect(pluginErrorCode(StateError('x')), isNull);
  });
}
