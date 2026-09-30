import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/syncplay/syncplay_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SyncPlayApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SyncPlayApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Map<String, dynamic>? body() =>
      adapter.requests.single.data as Map<String, dynamic>?;

  test('create, join, leave', () async {
    await api.create('Mario · Dune');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/SyncPlay/New');
    expect(body(), {'GroupName': 'Mario · Dune'});

    adapter.requests.clear();
    await api.join('g1');
    expect(adapter.requests.single.path, '/SyncPlay/Join');
    expect(body(), {'GroupId': 'g1'});

    adapter.requests.clear();
    await api.leave();
    expect(adapter.requests.single.path, '/SyncPlay/Leave');
  });

  test('create accetta anche la risposta 200 con il gruppo', () async {
    adapter.handler = (_) => const FakeResponse(200, {'GroupId': 'g1'});
    await api.create('Mario · Dune');
    expect(adapter.requests.single.path, '/SyncPlay/New');
  });

  test('list legge i gruppi e scarta quelli non validi', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {
            'GroupId': 'g1',
            'GroupName': 'Mario · Dune',
            'State': 'Paused',
            'Participants': ['Mario'],
            'LastUpdatedAt': '2026-09-30T10:00:00Z',
          },
          {'GroupName': 'senza id'},
        ]);
    final groups = await api.list();
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/SyncPlay/List');
    expect(groups.single.id, 'g1');
    expect(groups.single.state, GroupState.paused);
  });

  test('list con una risposta non valida', () async {
    adapter.handler = (_) => const FakeResponse(200, {'non': 'lista'});
    expect(api.list(), throwsA(isA<ServerErrorException>()));
  });

  test('coda, pausa, ripresa, salto', () async {
    await api.setNewQueue(['m1'], start: const Duration(minutes: 1));
    expect(adapter.requests.single.path, '/SyncPlay/SetNewQueue');
    expect(body(), {
      'PlayingQueue': ['m1'],
      'PlayingItemPosition': 0,
      'StartPositionTicks': 600000000,
    });

    adapter.requests.clear();
    await api.pause();
    expect(adapter.requests.single.path, '/SyncPlay/Pause');

    adapter.requests.clear();
    await api.unpause();
    expect(adapter.requests.single.path, '/SyncPlay/Unpause');

    adapter.requests.clear();
    await api.seek(const Duration(seconds: 90));
    expect(adapter.requests.single.path, '/SyncPlay/Seek');
    expect(body(), {'PositionTicks': 900000000});
  });

  test('buffering, ready, ping', () async {
    final state = ClientPlaybackState(
      when: DateTime.utc(2026, 9, 30, 10),
      position: const Duration(minutes: 10),
      isPlaying: true,
      playlistItemId: 'p1',
    );
    await api.buffering(state);
    expect(adapter.requests.single.path, '/SyncPlay/Buffering');
    expect(body(), {
      'When': '2026-09-30T10:00:00.000Z',
      'PositionTicks': 6000000000,
      'IsPlaying': true,
      'PlaylistItemId': 'p1',
    });

    adapter.requests.clear();
    await api.ready(state);
    expect(adapter.requests.single.path, '/SyncPlay/Ready');
    expect(body()!['PlaylistItemId'], 'p1');

    adapter.requests.clear();
    await api.ping(const Duration(milliseconds: 42));
    expect(adapter.requests.single.path, '/SyncPlay/Ping');
    expect(body(), {'Ping': 42});
  });

  test('utcTime legge i due istanti del server', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'RequestReceptionTime': '2026-09-30T10:00:00.1000000Z',
          'ResponseTransmissionTime': '2026-09-30T10:00:00.1050000Z',
        });
    final time = await api.utcTime();
    expect(adapter.requests.single.path, '/GetUtcTime');
    expect(time.requestReceived, DateTime.utc(2026, 9, 30, 10, 0, 0, 100));
    expect(time.responseSent, DateTime.utc(2026, 9, 30, 10, 0, 0, 105));
  });

  test('utcTime con una risposta non valida', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Boh': 1});
    expect(api.utcTime(), throwsA(isA<ServerErrorException>()));
  });

  test('group legge il gruppo; null se non esiste più', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'GroupId': 'g1',
          'GroupName': 'Mario · Dune',
          'State': 'Playing',
          'Participants': ['Mario', 'Luigi'],
          'LastUpdatedAt': '2026-09-30T10:00:00Z',
        });
    final group = await api.group('g1');
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/SyncPlay/g1');
    expect(group?.id, 'g1');
    expect(group?.state, GroupState.playing);
    expect(group?.participants, ['Mario', 'Luigi']);

    adapter.handler = (_) => const FakeResponse(404);
    expect(await api.group('g1'), isNull);

    adapter.handler = (_) => const FakeResponse(200, {'GroupName': 'senza id'});
    expect(api.group('g1'), throwsA(isA<ServerErrorException>()));
  });

  test('nextItem con l\'elemento in riproduzione', () async {
    await api.nextItem('p1');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/SyncPlay/NextItem');
    expect(body(), {'PlaylistItemId': 'p1'});
  });
}
