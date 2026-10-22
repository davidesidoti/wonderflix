import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/match_models.dart';

void main() {
  test('lo stato del plugin', () {
    final state = MatchState.fromJson({
      'RoomId': 'r1',
      'Rev': 4,
      'Phase': 'Voting',
      'CreatorId': 'u1',
      'CreatorName': 'Mario',
      'Members': [
        {'UserId': 'u1', 'Name': 'Mario', 'Voted': 3},
        {'UserId': 'u2', 'Name': 'Luigi', 'Voted': 1},
      ],
      'Stack': ['m1', 'm2', 'm3'],
      'Matches': ['m1'],
      'NearMatches': [
        {'ItemId': 'm2', 'Yes': 1, 'Of': 2},
      ],
    });

    expect(state.roomId, 'r1');
    expect(state.rev, 4);
    expect(state.phase, MatchPhase.voting);
    expect(state.creatorName, 'Mario');
    expect([for (final m in state.members) '${m.userId} ${m.name} ${m.voted}'],
        ['u1 Mario 3', 'u2 Luigi 1']);
    expect(state.stack, ['m1', 'm2', 'm3']);
    expect(state.matches, ['m1']);
    expect(state.nearMatches.single.itemId, 'm2');
    expect((state.nearMatches.single.yes, state.nearMatches.single.of), (1, 2));
    expect(state.closedReason, isNull);
    expect(state.partyGroupId, isNull);
  });

  test('una sala chiusa con il party', () {
    final state = MatchState.fromJson({
      'RoomId': 'r1',
      'Rev': 9,
      'Phase': 'Closed',
      'CreatorId': 'u1',
      'CreatorName': 'Mario',
      'Members': [],
      'Stack': [],
      'Matches': [],
      'NearMatches': [],
      'ClosedReason': 'PartyStarted',
      'PartyGroupId': 'g1',
    });

    expect(state.phase, MatchPhase.closed);
    expect(state.closedReason, MatchClosedReason.partyStarted);
    expect(state.partyGroupId, 'g1');
  });

  test('valori sconosciuti e liste mancanti', () {
    final state = MatchState.fromJson(
        {'RoomId': 'r1', 'Rev': 1, 'Phase': 'Boh', 'CreatorId': 'u1'});

    expect(state.phase, MatchPhase.closed);
    expect(state.creatorName, '');
    expect(state.members, isEmpty);
    expect(state.stack, isEmpty);
    expect(MatchClosedReason.fromWire('Boh'), isNull);
  });

  test('creatore e membri con gli id normalizzati', () {
    final state = MatchState.fromJson({
      'RoomId': 'r1',
      'Rev': 1,
      'Phase': 'Waiting',
      'CreatorId': 'abcdef0123456789abcdef0123456789',
      'Members': [
        {'UserId': 'abcdef0123456789abcdef0123456789', 'Name': 'Mario'},
      ],
    });

    expect(state.isCreator('ABCDEF01-2345-6789-ABCD-EF0123456789'), isTrue);
    expect(state.hasMember('abcdef01-2345-6789-abcd-ef0123456789'), isTrue);
    expect(state.isCreator('u2'), isFalse);
    expect(state.members.single.voted, 0);
  });
}
