import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/party_mode.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SocialApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SocialApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('info', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Version': '1.1.0',
          'Protocol': 1,
          'Features': ['friends'],
        });
    final info = await api.info();
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Info');
    expect(info.features, {'friends'});
  });

  test('amici', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Friends': [
            {'UserId': 'u2', 'Name': 'Luigi', 'Online': true, 'Party': null},
          ],
          'Incoming': [],
          'Outgoing': [],
        });
    final snapshot = await api.friends();
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Friends');
    expect(snapshot.friends.single.name, 'Luigi');
  });

  test('ricerca', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {'UserId': 'u2', 'Name': 'Luigi', 'Relation': 'None'},
        ]);
    final results = await api.search('lui');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Users/Search');
    expect(adapter.requests.single.queryParameters, {'q': 'lui'});
    expect(results.single.relation, FriendRelation.none);
  });

  test('azioni', () async {
    await api.request('u2');
    await api.accept('u2');
    await api.decline('u2');
    await api.cancel('u2');
    await api.remove('u2');
    expect(
        adapter.requests.map((r) => '${r.method} ${r.path}'),
        [
          'POST /WonderFlixWatchParty/Friends/Requests/u2',
          'POST /WonderFlixWatchParty/Friends/Requests/u2/Accept',
          'POST /WonderFlixWatchParty/Friends/Requests/u2/Decline',
          'DELETE /WonderFlixWatchParty/Friends/Requests/u2',
          'DELETE /WonderFlixWatchParty/Friends/u2',
        ]);
  });

  test('errori', () async {
    Future<SocialFailure?> failureOf(FakeResponse response) async {
      adapter.handler = (_) => response;
      try {
        await api.request('u2');
        return null;
      } on SocialException catch (error) {
        return error.failure;
      }
    }

    expect(await failureOf(const FakeResponse(404)), SocialFailure.unavailable);
    expect(await failureOf(const FakeResponse(400)), SocialFailure.forbidden);
    expect(await failureOf(const FakeResponse(403)), SocialFailure.forbidden);
    expect(await failureOf(const FakeResponse(409)), SocialFailure.conflict);
    expect(
        await failureOf(const FakeResponse(429)), SocialFailure.rateLimited);
    expect(await failureOf(const FakeResponse(500)), SocialFailure.network);
    adapter.handler = (_) => throw const SocketException('giù');
    await expectLater(
        api.friends(),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.network)));
    adapter.handler = (_) => const FakeResponse(200, {'Version': 3});
    await expectLater(
        api.info(),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.network)));
  });

  test('esiti previsti nel log come info, il resto come avviso', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    // Accettare una richiesta già annullata è una corsa normale (403).
    for (final status in [403, 404, 409, 429, 500]) {
      adapter.handler = (_) => FakeResponse(status);
      await expectLater(
          api.accept('u2'), throwsA(isA<SocialException>()));
    }

    expect([
      for (final record in records)
        if (record.loggerName == 'http') record.level,
    ], [Level.INFO, Level.INFO, Level.INFO, Level.INFO, Level.WARNING]);
  });

  test('party: registrazione, elenco, dettagli, codice, inviti', () async {
    adapter.handler = (options) => switch ('${options.method} ${options.path}') {
          'POST /WonderFlixWatchParty/Parties/g1' =>
            const FakeResponse(200, {'Code': 'K7PQ2X'}),
          'GET /WonderFlixWatchParty/Parties' => const FakeResponse(200, [
              {
                'GroupId': 'g1',
                'Name': 'Mario · Dune',
                'State': 'Idle',
                'Participants': ['Mario'],
                'Mode': 'Private',
              },
            ]),
          'GET /WonderFlixWatchParty/Parties/g1' =>
            const FakeResponse(200, {'Mode': 'Private', 'Code': 'K7PQ2X'}),
          'POST /WonderFlixWatchParty/Parties/Join' =>
            const FakeResponse(200, {'GroupId': 'g1'}),
          _ => const FakeResponse(204),
        };

    expect(await api.registerParty('g1', PartyMode.private), 'K7PQ2X');
    expect(adapter.requests.last.data, {'Mode': 'Private'});
    expect((await api.parties()).single.mode, PartyMode.private);
    expect((await api.partyDetails('g1')).code, 'K7PQ2X');
    expect(await api.joinByCode('K7PQ2X'), 'g1');
    expect(adapter.requests.last.data, {'Code': 'K7PQ2X'});
    await api.invite('g1', ['u2', 'u3']);
    expect(adapter.requests.last.path,
        '/WonderFlixWatchParty/Parties/g1/Invites');
    expect(adapter.requests.last.data, {
      'UserIds': ['u2', 'u3'],
    });
  });

  test('cassetta: lettura, letto, rimozione, svuota', () async {
    adapter.handler = (options) =>
        switch ('${options.method} ${options.path}') {
          'GET /WonderFlixWatchParty/Inbox' => const FakeResponse(200, {
              'Entries': [
                {
                  'Id': 'a1',
                  'Seq': 1,
                  'Type': 'Announcement',
                  'CreatedAt': '2026-10-03T20:00:00+00:00',
                  'Read': false,
                  'Text': 'ciao',
                },
              ],
              'Unread': 1,
            }),
          _ => const FakeResponse(204),
        };

    final inbox = await api.inbox();
    expect((inbox.entries.single as AnnouncementEntry).text, 'ciao');
    expect(inbox.unread, 1);
    await api.markInboxRead(7);
    expect(adapter.requests.last.data, {'UpTo': 7});
    await api.removeInboxEntry('a1');
    await api.clearInbox();
    expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
      'GET /WonderFlixWatchParty/Inbox',
      'POST /WonderFlixWatchParty/Inbox/Read',
      'DELETE /WonderFlixWatchParty/Inbox/Entries/a1',
      'DELETE /WonderFlixWatchParty/Inbox',
    ]);
  });

  test('party: registrazione senza codice e codice sbagliato', () async {
    adapter.handler = (_) => const FakeResponse(200, <String, dynamic>{});
    expect(await api.registerParty('g1', PartyMode.public), isNull);
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(
        api.joinByCode('ZZZZZZ'),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.forbidden)));
  });
}
