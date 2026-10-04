import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';

void main() {
  test('GroupInfo dal JSON', () {
    final info = GroupInfo.fromJson({
      'GroupId': 'g1',
      'GroupName': 'Mario · Dune',
      'State': 'Playing',
      'Participants': ['Mario', 'Luigi'],
      'LastUpdatedAt': '2026-09-30T10:00:00.1234567Z',
    });
    expect(info.id, 'g1');
    expect(info.name, 'Mario · Dune');
    expect(info.state, GroupState.playing);
    expect(info.participants, ['Mario', 'Luigi']);
    expect(info.lastUpdatedAt, DateTime.utc(2026, 9, 30, 10, 0, 0, 123, 456));
  });

  test('GroupInfo: stato sconosciuto e campi mancanti', () {
    final info = GroupInfo.fromJson({'GroupId': 'g1', 'State': 'Nuovo'});
    expect(info.name, '');
    expect(info.state, GroupState.idle);
    expect(info.participants, isEmpty);
  });

  test('SyncPlayCommand dal JSON', () {
    final command = SyncPlayCommand.fromJson({
      'GroupId': 'g1',
      'PlaylistItemId': 'p1',
      'When': '2026-09-30T10:00:01Z',
      'PositionTicks': 6000000000,
      'Command': 'Unpause',
      'EmittedAt': '2026-09-30T10:00:00Z',
    })!;
    expect(command.groupId, 'g1');
    expect(command.playlistItemId, 'p1');
    expect(command.when, DateTime.utc(2026, 9, 30, 10, 0, 1));
    expect(command.position, const Duration(minutes: 10));
    expect(command.type, SyncPlayCommandType.unpause);
    expect(command.emittedAt, DateTime.utc(2026, 9, 30, 10));
  });

  test('SyncPlayCommand: posizione nulla, comando sconosciuto', () {
    final stop = SyncPlayCommand.fromJson({
      'GroupId': 'g1',
      'PlaylistItemId': '',
      'When': '2026-09-30T10:00:01Z',
      'PositionTicks': null,
      'Command': 'Stop',
      'EmittedAt': '2026-09-30T10:00:00Z',
    })!;
    expect(stop.position, Duration.zero);
    expect(stop.type, SyncPlayCommandType.stop);
    expect(
        SyncPlayCommand.fromJson({
          'GroupId': 'g1',
          'When': '2026-09-30T10:00:01Z',
          'Command': 'Rewind',
          'EmittedAt': '2026-09-30T10:00:00Z',
        }),
        isNull);
    expect(SyncPlayCommand.fromJson({'Command': 'Pause'}), isNull);
  });

  test('sameAs confronta comando, istante, posizione ed elemento', () {
    SyncPlayCommand command({String item = 'p1', int seconds = 1}) =>
        SyncPlayCommand(
          groupId: 'g1',
          playlistItemId: item,
          when: DateTime.utc(2026, 9, 30, 10, 0, seconds),
          position: const Duration(minutes: 10),
          type: SyncPlayCommandType.pause,
          emittedAt: DateTime.utc(2026, 9, 30, 10, 0, seconds),
        );
    expect(command().sameAs(command()), isTrue);
    expect(command().sameAs(command(item: 'p2')), isFalse);
    expect(command().sameAs(command(seconds: 2)), isFalse);
  });

  test('parseGroupUpdate: tutti i tipi', () {
    Map<String, dynamic> update(String type, Object? data) =>
        {'GroupId': 'g1', 'Type': type, 'Data': data};

    final joined = parseGroupUpdate(update('GroupJoined', {
      'GroupId': 'g1',
      'GroupName': 'Mario · Dune',
      'State': 'Idle',
      'Participants': ['Mario'],
      'LastUpdatedAt': '2026-09-30T10:00:00Z',
    }));
    expect(joined, isA<GroupJoined>());
    expect((joined as GroupJoined).info.participants, ['Mario']);
    expect(joined.groupId, 'g1');

    expect((parseGroupUpdate(update('UserJoined', 'Luigi')) as UserJoined)
            .userName,
        'Luigi');
    expect((parseGroupUpdate(update('UserLeft', 'Luigi')) as UserLeft)
            .userName,
        'Luigi');
    expect(parseGroupUpdate(update('GroupLeft', 'g1')), isA<GroupLeft>());
    expect(parseGroupUpdate(update('NotInGroup', '')), isA<NotInGroup>());
    expect(parseGroupUpdate(update('GroupDoesNotExist', '')),
        isA<GroupDoesNotExist>());
    expect(parseGroupUpdate(update('LibraryAccessDenied', '')),
        isA<LibraryAccessDenied>());

    final state = parseGroupUpdate(
        update('StateUpdate', {'State': 'Waiting', 'Reason': 'Buffer'}));
    expect((state as GroupStateUpdate).state, GroupState.waiting);
    expect(state.reason, 'Buffer');

    final queue = parseGroupUpdate(update('PlayQueue', {
      'Reason': 'NewPlaylist',
      'LastUpdate': '2026-09-30T10:00:00Z',
      'Playlist': [
        {'ItemId': 'm1', 'PlaylistItemId': 'p1'},
        {'ItemId': 'm2', 'PlaylistItemId': 'p2'},
      ],
      'PlayingItemIndex': 1,
      'StartPositionTicks': 600000000,
      'IsPlaying': true,
      'ShuffleMode': 'Sorted',
      'RepeatMode': 'RepeatNone',
    }));
    final playQueue = (queue as PlayQueueUpdate).queue;
    expect(playQueue.reason, 'NewPlaylist');
    expect(playQueue.lastUpdate, DateTime.utc(2026, 9, 30, 10));
    expect(playQueue.entries.map((e) => e.itemId), ['m1', 'm2']);
    expect(playQueue.playing?.playlistItemId, 'p2');
    expect(playQueue.startPosition, const Duration(minutes: 1));
    expect(playQueue.isPlaying, isTrue);
  });

  test('parseGroupUpdate: forme non valide', () {
    expect(parseGroupUpdate(null), isNull);
    expect(parseGroupUpdate({'GroupId': 'g1', 'Type': 'Sconosciuto'}),
        isNull);
    expect(parseGroupUpdate({'GroupId': 'g1', 'Type': 'GroupJoined', 'Data': 3}),
        isNull);
  });

  test('coda senza elemento in riproduzione', () {
    final queue = PlayQueue.fromJson({
      'Reason': 'RemoveItems',
      'LastUpdate': '2026-09-30T10:00:00Z',
      'Playlist': [],
      'PlayingItemIndex': -1,
    });
    expect(queue.playing, isNull);
    expect(queue.startPosition, Duration.zero);
    expect(queue.isPlaying, isFalse);
  });

  test('PlayQueue: ordine casuale (spec H §8.1)', () {
    final queue = PlayQueue.fromJson({
      'Reason': 'ShuffleMode',
      'LastUpdate': '2026-10-04T10:00:00Z',
      'Playlist': [
        {'ItemId': 'e4', 'PlaylistItemId': 'p1'},
      ],
      'PlayingItemIndex': 0,
      'ShuffleMode': 'Shuffle',
    });
    expect(queue.shuffled, isTrue);
    expect(PlayQueue.fromJson({'ShuffleMode': 'Sorted'}).shuffled, isFalse);
    expect(PlayQueue.fromJson(const <String, dynamic>{}).shuffled, isFalse);
  });
}
