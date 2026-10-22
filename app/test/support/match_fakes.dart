import 'dart:async';
import 'dart:convert';

import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/core/social/match_models.dart';

/// Una sala di prova: `r1`, aperta da Mario (`testUser`), in attesa.
MatchState testMatchState({
  String roomId = 'r1',
  int rev = 1,
  MatchPhase phase = MatchPhase.waiting,
  String creatorId = 'u1',
  String creatorName = 'Mario',
  List<MatchMember> members = const [
    MatchMember(userId: 'u1', name: 'Mario', voted: 0),
  ],
  List<String> stack = const [],
  List<String> matches = const [],
  List<MatchNearMatch> nearMatches = const [],
  MatchClosedReason? closedReason,
  String? partyGroupId,
}) =>
    MatchState(
      roomId: roomId,
      rev: rev,
      phase: phase,
      creatorId: creatorId,
      creatorName: creatorName,
      members: members,
      stack: stack,
      matches: matches,
      nearMatches: nearMatches,
      closedReason: closedReason,
      partyGroupId: partyGroupId,
    );

/// Il JSON di [state], come lo manda il plugin.
Map<String, Object?> matchStateJson(MatchState state) => {
      'RoomId': state.roomId,
      'Rev': state.rev,
      'Phase': state.phase.wire,
      'CreatorId': state.creatorId,
      'CreatorName': state.creatorName,
      'Members': [
        for (final member in state.members)
          {'UserId': member.userId, 'Name': member.name, 'Voted': member.voted},
      ],
      'Stack': state.stack,
      'Matches': state.matches,
      'NearMatches': [
        for (final near in state.nearMatches)
          {'ItemId': near.itemId, 'Yes': near.yes, 'Of': near.of},
      ],
      'ClosedReason': ?state.closedReason?.wire,
      'PartyGroupId': ?state.partyGroupId,
    };

/// Come arriva dal WebSocket lo stato di una sala.
PartyChannelReceived matchUpdatedReceived(MatchState state) =>
    PartyChannelReceived(jsonEncode({
      'Protocol': 1,
      'Type': 'MatchUpdated',
      'State': matchStateJson(state),
    }));

/// Come arriva dal WebSocket l'invito a una sala.
PartyChannelReceived matchInviteReceived(String roomId, String fromName) =>
    PartyChannelReceived(jsonEncode({
      'Protocol': 1,
      'Type': 'MatchInvite',
      'FromName': fromName,
      'RoomId': roomId,
    }));

/// Plugin del match finto: le sale in [rooms], ogni chiamata in [calls]
/// (`open`, `state r1`, `invite r1 u2,u3`, `join r1`, `leave r1`,
/// `start r1 movies any -`, `vote r1 m1 yes`, `more r1`, `party r1 g1`).
class FakeMatchApi implements MatchApi {
  final calls = <String>[];

  /// Le sale per id: `state`, `join` e `more` rispondono con questa.
  final rooms = <String, MatchState>{};

  /// La sala che crea il prossimo [open].
  String nextRoomId = 'r1';

  /// Errori per chiamata (la stringa di [calls]): valgono una volta.
  final failures = <String, MatchException>{};

  /// Errori per chiamata che valgono sempre.
  final failAlways = <String, MatchException>{};

  /// Se valorizzato, [open] e [join] aspettano che si completi.
  Completer<void>? enterGate;

  void _throwIfFailing(String call) {
    final error = failures.remove(call) ?? failAlways[call];
    if (error != null) throw error;
  }

  @override
  Future<MatchState> open() async {
    calls.add('open');
    await enterGate?.future;
    _throwIfFailing('open');
    return rooms[nextRoomId] ??= testMatchState(roomId: nextRoomId);
  }

  @override
  Future<MatchState> state(String roomId) async {
    calls.add('state $roomId');
    _throwIfFailing('state $roomId');
    return rooms[roomId] ??
        (throw const MatchException(MatchFailure.notMember));
  }

  @override
  Future<void> invite(String roomId, List<String> userIds) async {
    final call = 'invite $roomId ${userIds.join(',')}';
    calls.add(call);
    _throwIfFailing(call);
  }

  @override
  Future<MatchState> join(String roomId) async {
    calls.add('join $roomId');
    await enterGate?.future;
    _throwIfFailing('join $roomId');
    return rooms[roomId] ?? (throw const MatchException(MatchFailure.closed));
  }

  @override
  Future<void> leave(String roomId) async {
    calls.add('leave $roomId');
    _throwIfFailing('leave $roomId');
  }

  @override
  Future<MatchState> start(String roomId,
      {required String type,
      required String duration,
      String? genre,
      required String rating}) async {
    final call = 'start $roomId $type $duration ${genre ?? '-'} $rating';
    calls.add(call);
    _throwIfFailing(call);
    final room = rooms[roomId] ?? testMatchState(roomId: roomId);
    return rooms[roomId] = testMatchState(
      roomId: roomId,
      rev: room.rev + 1,
      phase: MatchPhase.voting,
      creatorId: room.creatorId,
      creatorName: room.creatorName,
      members: room.members,
    );
  }

  @override
  Future<void> vote(String roomId, String itemId, {required bool yes}) async {
    final call = 'vote $roomId $itemId ${yes ? 'yes' : 'no'}';
    calls.add(call);
    _throwIfFailing(call);
  }

  @override
  Future<MatchState> more(String roomId) async {
    calls.add('more $roomId');
    _throwIfFailing('more $roomId');
    return rooms[roomId] ?? (throw const MatchException(MatchFailure.closed));
  }

  @override
  Future<void> party(String roomId, String groupId) async {
    final call = 'party $roomId $groupId';
    calls.add(call);
    _throwIfFailing(call);
  }
}
