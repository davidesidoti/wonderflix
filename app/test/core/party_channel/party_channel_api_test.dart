import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/party_channel/party_channel_api.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late PartyChannelApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = PartyChannelApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Map<String, dynamic> chat(String id, String text) => {
        'Protocol': 1,
        'Id': id,
        'GroupId': 'g1',
        'UserId': 'u2',
        'UserName': 'Luigi',
        'SentAt': '2026-10-02T21:00:00Z',
        'Type': 'Chat',
        'Text': text,
      };

  test('info', () async {
    adapter.handler =
        (_) => const FakeResponse(200, {'Version': '1.0.0', 'Protocol': 1});
    final info = await api.info();
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Info');
    expect(info.version, '1.0.0');
    expect(info.protocol, 1);
  });

  test('join: storico della chat, scarta il resto', () async {
    adapter.handler = (_) => FakeResponse(200, {
          'Messages': [
            chat('e1', 'ciao'),
            {'Type': 'Chat'},
            chat('e2', 'pronti?'),
          ],
        });
    final history = await api.join('g1');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Groups/g1/Join');
    expect(history.map((event) => event.text), ['ciao', 'pronti?']);
  });

  test('leave', () async {
    await api.leave('g1');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Groups/g1/Leave');
  });

  test('send: corpo e risposta timbrata', () async {
    adapter.handler = (_) => FakeResponse(200, chat('e9', 'che scena'));
    final stamped = await api.send('g1', const PartyOutgoingChat('che scena'));
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Groups/g1/Events');
    expect(adapter.requests.single.data, {'Type': 'Chat', 'Text': 'che scena'});
    expect((stamped as PartyChatEvent).id, 'e9');
  });

  Future<PartyChannelFailure> failure(int status) async {
    adapter.handler = (_) => FakeResponse(status, {'error': 'x'});
    try {
      await api.send('g1', const PartyOutgoingChat('x'));
    } on PartyChannelException catch (error) {
      return error.failure;
    }
    fail('nessun errore con $status');
  }

  test('errori classificati (spec E §6.2)', () async {
    expect(await failure(404), PartyChannelFailure.unavailable);
    expect(await failure(400), PartyChannelFailure.rejected);
    expect(await failure(401), PartyChannelFailure.rejected);
    expect(await failure(403), PartyChannelFailure.rejected);
    expect(await failure(409), PartyChannelFailure.sessionUnknown);
    expect(await failure(429), PartyChannelFailure.rateLimited);
    expect(await failure(500), PartyChannelFailure.network);
  });

  test('404 e 429 del plugin vanno nel log come info, non tra gli errori',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(api.info(), throwsA(isA<PartyChannelException>()));
    await expectLater(api.join('g1'), throwsA(isA<PartyChannelException>()));
    await expectLater(api.leave('g1'), throwsA(isA<PartyChannelException>()));
    adapter.handler = (_) => const FakeResponse(429);
    await expectLater(api.send('g1', const PartyOutgoingChat('x')),
        throwsA(isA<PartyChannelException>()));
    adapter.handler = (_) => const FakeResponse(500);
    await expectLater(api.info(), throwsA(isA<PartyChannelException>()));

    expect([
      for (final record in records)
        if (record.loggerName == 'http') (record.level, record.message),
    ], [
      (Level.INFO, 'GET /WonderFlixWatchParty/Info: 404'),
      (Level.INFO, 'POST /WonderFlixWatchParty/Groups/g1/Join: 404'),
      (Level.INFO, 'POST /WonderFlixWatchParty/Groups/g1/Leave: 404'),
      (Level.INFO, 'POST /WonderFlixWatchParty/Groups/g1/Events: 429'),
      (Level.WARNING, 'GET /WonderFlixWatchParty/Info: 500'),
    ]);
  });

  test('rete assente e risposte di forma inattesa', () async {
    Matcher failsWith(PartyChannelFailure failure) =>
        throwsA(isA<PartyChannelException>()
            .having((error) => error.failure, 'failure', failure));

    adapter.handler = (_) => throw const SocketException('offline');
    await expectLater(api.info(), failsWith(PartyChannelFailure.network));

    adapter.handler = (_) => const FakeResponse(200, {'Version': '1.0.0'});
    await expectLater(api.info(), failsWith(PartyChannelFailure.network));

    adapter.handler = (_) => const FakeResponse(200, {'Type': 'Chat'});
    await expectLater(api.send('g1', const PartyOutgoingChat('x')),
        failsWith(PartyChannelFailure.network));
  });
}
