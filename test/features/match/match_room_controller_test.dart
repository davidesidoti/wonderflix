import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/match_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeMatchApi api;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeMatchApi();
    events = StreamController<ServerEvent>.broadcast();
    container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        socialAvailabilityProvider.overrideWith(() =>
            FakeSocialAvailability(const SocialFeatures(friends: true, match: true))),
        matchApiProvider.overrideWithValue(api),
      ],
      retry: (_, _) => null,
    );
    container.listen(matchRoomProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await events.close();
  });

  MatchRoomController controller() => container.read(matchRoomProvider.notifier);
  MatchRoomView? room() => container.read(matchRoomProvider);

  const luigi = MatchMember(userId: 'u2', name: 'Luigi', voted: 0);
  const mario = MatchMember(userId: 'u1', name: 'Mario', voted: 0);

  Future<void> push(MatchState state) async {
    events.add(matchUpdatedReceived(state));
    await pumpEventQueue();
  }

  test('aprire una sala la tiene nell\'app', () async {
    expect(await controller().open(), isNull);
    expect(room()!.roomId, 'r1');
    expect(room()!.state!.phase, MatchPhase.waiting);
    expect(room()!.closed, isFalse);
    expect(api.calls, ['open']);
  });

  test('aGhostRoomIsLeftAndOpenRetried', () async {
    api.failures['open'] =
        const MatchException(MatchFailure.inAnotherRoom, roomId: 'r9');

    expect(await controller().open(), isNull);

    expect(api.calls, ['open', 'leave r9', 'open']);
    expect(room()!.roomId, 'r1');
  });

  test('la sala fantasma si lascia una volta sola', () async {
    api.failAlways['open'] =
        const MatchException(MatchFailure.inAnotherRoom, roomId: 'r9');

    expect(await controller().open(), MatchFailure.inAnotherRoom);

    expect(api.calls, ['open', 'leave r9', 'open']);
    expect(room(), isNull);
  });

  test('la sala che l\'app mostra non è una sala fantasma', () async {
    await controller().open();
    api.failures['join r2'] =
        const MatchException(MatchFailure.inAnotherRoom, roomId: 'r1');

    expect(await controller().join('r2'), MatchFailure.inAnotherRoom);

    expect(api.calls, ['open', 'join r2']);
    expect(room()!.roomId, 'r1');
  });

  test('entrare su invito; i motivi del no', () async {
    api.rooms['r2'] = testMatchState(
        roomId: 'r2', creatorId: 'u2', creatorName: 'Luigi', members: [luigi, mario]);

    expect(await controller().join('r2'), isNull);
    expect(room()!.state!.creatorName, 'Luigi');

    await controller().leave();
    api.failures['join r3'] = const MatchException(MatchFailure.started);
    expect(await controller().join('r3'), MatchFailure.started);
    expect(room(), isNull);
  });

  test('entering vale mentre si entra', () async {
    api.enterGate = Completer<void>();
    final opening = controller().open();
    await pumpEventQueue();
    expect(controller().entering, isTrue);

    api.enterGate!.complete();
    await opening;
    expect(controller().entering, isFalse);
  });

  test('onlyNewerStatesOfTheOwnRoomCount', () async {
    await controller().open();

    await push(testMatchState(rev: 3, members: [mario, luigi]));
    expect(room()!.state!.rev, 3);
    expect(room()!.state!.members, hasLength(2));

    await push(testMatchState(rev: 2));
    await push(testMatchState(rev: 3));
    await push(testMatchState(roomId: 'r2', rev: 9));
    expect(room()!.roomId, 'r1');
    expect(room()!.state!.rev, 3);
    expect(room()!.state!.members, hasLength(2));
  });

  test('alla riconnessione si rilegge; fuori dalla sala diventa gone', () async {
    await controller().open();

    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(api.calls, ['open'], reason: 'la prima connessione non rilegge');

    api.rooms['r1'] = testMatchState(rev: 5);
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls.last, 'state r1');
    expect(room()!.state!.rev, 5);

    api.rooms.remove('r1');
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(room()!.gone, isTrue);
    expect(room()!.closed, isTrue);
  });

  test('uscire: solo dalla propria sala, e non da una sala chiusa', () async {
    await controller().open();

    await controller().leave('r2');
    expect(room()!.roomId, 'r1');

    await controller().leave('r1');
    expect(room(), isNull);
    expect(api.calls.last, 'leave r1');

    await controller().open();
    await push(testMatchState(
        rev: 2,
        phase: MatchPhase.closed,
        closedReason: MatchClosedReason.creatorLeft));
    expect(room()!.closed, isTrue);
    final calls = api.calls.length;
    await controller().leave();
    expect(room(), isNull);
    expect(api.calls, hasLength(calls));
  });

  test('un errore dell\'uscita non ferma niente', () async {
    await controller().open();
    api.failures['leave r1'] = const MatchException(MatchFailure.network);

    await controller().leave();

    expect(room(), isNull);
  });

  test('inviti e inizio passano i valori del plugin', () async {
    expect(await controller().invite(['u2']), MatchFailure.closed,
        reason: 'fuori da una sala');
    expect(api.calls, isEmpty);

    await controller().open();
    expect(await controller().invite(['u2', 'u3']), isNull);
    expect(api.calls.last, 'invite r1 u2,u3');

    expect(
        await controller().start(const TonightFilters(
            type: TonightType.movies,
            duration: TonightDuration.under90,
            genre: 'Horror')),
        isNull);
    expect(api.calls.last, 'start r1 movies 90 Horror');
    expect(room()!.state!.phase, MatchPhase.voting);

    api.failures['start r1 both any -'] =
        const MatchException(MatchFailure.notEnoughMembers);
    expect(await controller().start(const TonightFilters()),
        MatchFailure.notEnoughMembers);
  });

  test('senza la funzione match la sala sparisce', () async {
    await controller().open();
    (container.read(socialAvailabilityProvider.notifier)
            as FakeSocialAvailability)
        .set(SocialFeatures.none);
    await pumpEventQueue();

    expect(room(), isNull);
  });

  test('una seconda apertura mentre si entra è un conflitto', () async {
    api.enterGate = Completer<void>();
    final first = controller().open();
    await pumpEventQueue();

    expect(await controller().open(), MatchFailure.conflict);
    expect(api.calls, ['open']);

    api.enterGate!.complete();
    expect(await first, isNull);
  });

  test('una sala che arriva dopo un cambio di funzione non si tiene', () async {
    api.enterGate = Completer<void>();
    final opening = controller().open();
    await pumpEventQueue();

    final availability = container.read(socialAvailabilityProvider.notifier)
        as FakeSocialAvailability;
    availability.set(SocialFeatures.none);
    await pumpEventQueue();
    availability.set(const SocialFeatures(friends: true, match: true));
    await pumpEventQueue();
    api.enterGate!.complete();
    await opening;

    expect(room(), isNull);
  });

  Future<void> openVoting({List<MatchMember> members = const [mario]}) async {
    api.rooms['r1'] = testMatchState(
        rev: 2,
        phase: MatchPhase.voting,
        members: members,
        stack: ['m1', 'm2']);
    await controller().open();
  }

  test('votingMovesThePositionAtOnce', () async {
    await openVoting();

    expect(await controller().vote('m1', yes: true), isNull);

    expect(api.calls.last, 'vote r1 m1 yes');
    expect(room()!.position('u1'), 1);
  });

  test('aVoteForAnotherTitleIsRefused', () async {
    await openVoting();

    expect(await controller().vote('m2', yes: true), MatchFailure.notNext);

    expect(api.calls.where((c) => c.startsWith('vote')), isEmpty);
  });

  test('aFailedVoteGoesBack', () async {
    await openVoting();
    api.failures['vote r1 m1 yes'] = const MatchException(MatchFailure.network);

    expect(await controller().vote('m1', yes: true), MatchFailure.network);
    expect(room()!.position('u1'), 0);

    expect(await controller().vote('m1', yes: true), isNull);
    expect(room()!.position('u1'), 1);
  });

  test('notNextRealignsFromThePlugin', () async {
    await openVoting();
    api.failures['vote r1 m1 yes'] = const MatchException(MatchFailure.notNext);
    api.rooms['r1'] = testMatchState(
        rev: 3,
        phase: MatchPhase.voting,
        members: [const MatchMember(userId: 'u1', name: 'Mario', voted: 1)],
        stack: ['m1', 'm2']);

    expect(await controller().vote('m1', yes: true), MatchFailure.notNext);

    expect(api.calls, contains('state r1'));
    expect(room()!.position('u1'), 1);
    expect(room()!.sent, 0);
  });

  test('moreAppliesTheNewStack', () async {
    await openVoting();
    api.rooms['r1'] = testMatchState(
        rev: 4,
        phase: MatchPhase.voting,
        members: [const MatchMember(userId: 'u1', name: 'Mario', voted: 2)],
        stack: ['m1', 'm2', 'm3']);

    expect(await controller().more(), isNull);

    expect(api.calls.last, 'more r1');
    expect(room()!.state!.stack, hasLength(3));
  });

  test('partyCallsThePlugin', () async {
    expect(await controller().party('g1'), MatchFailure.closed);
    expect(api.calls, isEmpty);

    await openVoting();
    expect(await controller().party('g1'), isNull);
    expect(api.calls.last, 'party r1 g1');
  });

  test('aStateArrivingWhileEnteringIsKept', () async {
    api.enterGate = Completer<void>();
    final opening = controller().open();
    await pumpEventQueue();

    await push(testMatchState(roomId: 'r2', rev: 9));
    await push(testMatchState(rev: 5, members: [mario, luigi]));
    api.enterGate!.complete();
    await opening;

    expect(room()!.roomId, 'r1');
    expect(room()!.state!.rev, 5);
  });
}
