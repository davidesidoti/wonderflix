import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/match/match_actions.dart';
import 'package:wonderflix/features/match/match_celebration.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/match/match_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/tonight/tonight_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeMatchApi match;
  late FakeSocialApi social;
  late FakeLibraryApi library;
  late SharedPreferences prefs;
  late FakeSyncPlayApi syncPlay;
  late FakePartyChannelApi channelApi;
  late StreamController<ServerEvent> events;

  const mario = MatchMember(userId: 'u1', name: 'Mario', voted: 0);
  const luigi = MatchMember(userId: 'u2', name: 'Luigi', voted: 0);

  setUp(() async {
    match = FakeMatchApi();
    library = FakeLibraryApi();
    social = FakeSocialApi()
      ..snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true),
        testFriend('u3', 'Peach', online: true),
        testFriend('u4', 'Toad'),
      ]);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    syncPlay = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi()..install();
    events = StreamController<ServerEvent>.broadcast();
    syncPlay.onCall = (call) {
      if (call.startsWith('create') || call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  /// La Home finta con "apri" e la pagina della sala `r1` già aperta.
  Future<ProviderContainer> pumpRoom(WidgetTester tester,
      {MatchState? state}) async {
    match.rooms['r1'] = state ?? testMatchState();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => unawaited(openMatchRoom(context, ref)),
                child: const Text('apri'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/match/:id',
          builder: (context, state) => Scaffold(
              body: MatchScreen(roomId: state.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/item/:id',
          builder: (context, state) => const Scaffold(body: Text('scheda')),
        ),
      ],
    );
    await pumpAppRouter(tester, router, overrides: [
      ...socialTestOverrides(social,
          events: events.stream,
          features: const SocialFeatures(
              friends: true, parties: true, match: true)),
      syncPlayApiProvider.overrideWithValue(syncPlay),
      partyChannelApiProvider.overrideWithValue(channelApi),
      matchApiProvider.overrideWithValue(match),
      sharedPreferencesProvider.overrideWithValue(prefs),
      libraryApiProvider.overrideWithValue(library),
    ]);
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MatchScreen)));
  }

  testWidgets('chi ha aperto: filtri, amici online da invitare, Inizia spento',
      (tester) async {
    await pumpRoom(tester);

    expect(find.text('MATCH DEL FILM'), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);
    expect(find.byKey(const Key('tonight-type')), findsOneWidget);
    expect(find.text('Amici online'), findsOneWidget);
    expect(find.byKey(const Key('match-invite-u2')), findsOneWidget);
    expect(find.byKey(const Key('match-invite-u3')), findsOneWidget);
    expect(find.byKey(const Key('match-invite-u4')), findsNothing,
        reason: 'offline');
    expect(find.text('Serve almeno un amico nella sala'), findsOneWidget);
    expect(tester.widget<WfButton>(find.byKey(const Key('match-start'))).onPressed,
        isNull);
  });

  testWidgets('Invita manda l\'invito e diventa Invitato', (tester) async {
    await pumpRoom(tester);

    await tester.tap(find.byKey(const Key('match-invite-u2')));
    await tester.pumpAndSettle();

    expect(match.calls.last, 'invite r1 u2');
    expect(find.descendant(
            of: find.byKey(const Key('match-invite-u2')),
            matching: find.text('Invitato')),
        findsOneWidget);
  });

  testWidgets('con un amico dentro: niente invito per lui, Inizia con i filtri',
      (tester) async {
    prefs.setString(tonightTypeKey, 'movies');
    await pumpRoom(tester, state: testMatchState(members: [mario, luigi]));

    expect(find.byKey(const Key('match-invite-u2')), findsNothing);
    expect(find.text('Serve almeno un amico nella sala'), findsNothing);

    await tester.tap(find.byKey(const Key('match-start')));
    await tester.pumpAndSettle();

    expect(match.calls.last, 'start r1 movies any -');
  });

  testWidgets('chi è entrato su invito aspetta chi ha aperto', (tester) async {
    await pumpRoom(tester,
        state: testMatchState(
            creatorId: 'u2', creatorName: 'Luigi', members: [luigi, mario]));

    expect(find.text('In attesa che Luigi inizi…'), findsOneWidget);
    expect(find.byKey(const Key('match-start')), findsNothing);
    expect(find.byKey(const Key('tonight-type')), findsNothing);
  });

  testWidgets('leavingThePageLeavesTheRoomOnce', (tester) async {
    final container = await pumpRoom(tester);

    GoRouter.of(tester.element(find.byType(MatchScreen))).pop();
    await tester.pumpAndSettle();

    expect(match.calls.where((call) => call == 'leave r1'), hasLength(1));
    expect(container.read(matchRoomProvider), isNull);
  });

  testWidgets('una sala chiusa chiude la pagina con "Sala chiusa"',
      (tester) async {
    final container = await pumpRoom(tester);

    match.rooms['r1'] = testMatchState(
        rev: 2,
        phase: MatchPhase.closed,
        closedReason: MatchClosedReason.creatorLeft);
    await container.read(matchRoomProvider.notifier).reload();
    await tester.pumpAndSettle();

    expect(find.byType(MatchScreen), findsNothing);
    expect(find.text('Sala chiusa'), findsOneWidget);
    expect(match.calls.where((call) => call.startsWith('leave')), isEmpty,
        reason: 'una sala chiusa non si lascia');
  });

  testWidgets('chiudere la sala con una scheda sopra non toglie la scheda',
      (tester) async {
    final container = await pumpRoom(tester);
    final router = GoRouter.of(tester.element(find.byType(MatchScreen)));
    unawaited(router.push('/item/x'));
    await tester.pumpAndSettle();

    match.rooms['r1'] = testMatchState(
        rev: 2,
        phase: MatchPhase.closed,
        closedReason: MatchClosedReason.creatorLeft);
    await container.read(matchRoomProvider.notifier).reload();
    await tester.pumpAndSettle();

    expect(find.text('scheda'), findsOneWidget);
    expect(find.byType(MatchScreen, skipOffstage: false), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.byType(MatchScreen, skipOffstage: false), findsNothing);
    expect(find.text('apri'), findsOneWidget);
    expect(find.text('Sala chiusa'), findsOneWidget);
  });

  testWidgets('una pagina aperta su una sala già chiusa si chiude',
      (tester) async {
    final container = await pumpRoom(tester);
    match.rooms['r1'] = testMatchState(
        rev: 2,
        phase: MatchPhase.closed,
        closedReason: MatchClosedReason.inactive);
    await container.read(matchRoomProvider.notifier).reload();
    await tester.pumpAndSettle();
    expect(find.byType(MatchScreen), findsNothing);

    unawaited(GoRouter.of(tester.element(find.text('apri'))).push('/match/r1'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchScreen), findsNothing);
    expect(find.text('apri'), findsOneWidget);
  });

  testWidgets('Unisciti alla sala già mostrata non apre una seconda pagina',
      (tester) async {
    await pumpRoom(tester);
    final element = tester.element(find.byType(MatchScreen));
    final ref = tester.state<ConsumerState<MatchScreen>>(find.byType(MatchScreen)).ref;

    final joined = await joinMatchRoom(element, ref, 'r1');
    await tester.pumpAndSettle();

    expect(joined, isTrue);
    expect(match.calls, isNot(contains('join r1')));
    expect(find.byType(MatchScreen), findsOneWidget);
  });

  testWidgets("un genere salvato che non c'è più torna a tutti i generi",
      (tester) async {
    await prefs.setString(tonightGenreKey, 'Western');
    await pumpRoom(tester);
    await tester.pumpAndSettle();

    expect(prefs.getString(tonightGenreKey), isNull);
  });

  group('votazione', () {
    final votingState = testMatchState(
        phase: MatchPhase.voting,
        members: const [mario, luigi],
        stack: const ['m1', 'm2']);

    setUp(() {
      library.itemsById['m1'] = testItem(id: 'm1', name: 'Dune');
      library.itemsById['m2'] = testItem(id: 'm2', name: 'Alien');
    });

    testWidgets('theVotingPageShowsTheTopCard', (tester) async {
      await pumpRoom(tester, state: votingState);

      expect(find.text('Dune'), findsOneWidget);

      await tester.tap(find.byKey(const Key('match-yes')));
      await tester.pumpAndSettle();

      expect(match.calls, contains('vote r1 m1 yes'));
      expect(find.text('Alien'), findsOneWidget);
      expect(find.text('Dune'), findsNothing);
    });

    testWidgets('aFailedVoteBringsTheCardBack', (tester) async {
      match.failures['vote r1 m1 yes'] =
          const MatchException(MatchFailure.network);
      await pumpRoom(tester, state: votingState);

      await tester.tap(find.byKey(const Key('match-yes')));
      await tester.pumpAndSettle();

      expect(find.text('Voto non inviato'), findsOneWidget);
      expect(find.text('Dune').hitTestable(), findsOneWidget);

      // La carta è tornata davvero: un secondo voto parte.
      await tester.tap(find.byKey(const Key('match-yes')));
      await tester.pumpAndSettle();
      expect(match.calls.where((c) => c == 'vote r1 m1 yes'), hasLength(2));
      expect(find.text('Alien'), findsOneWidget);
    });

    testWidgets('aFailedMissingTitleVoteIsRetried', (tester) async {
      library.itemsById.remove('m1');
      match.failures['vote r1 m1 no'] =
          const MatchException(MatchFailure.network);
      await pumpRoom(tester, state: votingState);
      await tester.pumpAndSettle();
      expect(match.calls.where((c) => c == 'vote r1 m1 no'), hasLength(1));
      // Il voto non è dell'utente: niente avviso.
      expect(find.text('Voto non inviato'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(match.calls.where((c) => c == 'vote r1 m1 no'), hasLength(2));
      expect(find.text('Alien'), findsOneWidget);
    });

    Future<void> newState(WidgetTester tester, ProviderContainer container,
        {required List<String> matches, int rev = 2}) async {
      match.rooms['r1'] = testMatchState(
          rev: rev,
          phase: MatchPhase.voting,
          members: const [mario, luigi],
          stack: const ['m1', 'm2'],
          matches: matches);
      await container.read(matchRoomProvider.notifier).reload();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('aNewMatchIsCelebratedOnce', (tester) async {
      final container = await pumpRoom(tester, state: votingState);
      expect(find.text('È un match!'), findsNothing);

      await newState(tester, container, matches: const ['m1']);
      expect(find.text('È un match!'), findsOneWidget);

      await tester.pump(matchCelebrationDuration);
      await tester.pump();
      expect(find.text('È un match!'), findsNothing);

      await newState(tester, container, matches: const ['m1'], rev: 3);
      expect(find.text('È un match!'), findsNothing);
    });

    testWidgets('aKeyClosesTheCelebrationWithoutVoting', (tester) async {
      final container = await pumpRoom(tester, state: votingState);
      await newState(tester, container, matches: const ['m1']);
      expect(find.byKey(const Key('match-celebration-m1')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(find.byKey(const Key('match-celebration-m1')), findsNothing);
      expect(match.calls.where((c) => c.startsWith('vote')), isEmpty);

      // Chiusa la festa, la freccia torna a votare sul mazzo.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(match.calls, contains('vote r1 m1 yes'));
    });

    testWidgets('twoNewMatchesOneAfterTheOther', (tester) async {
      final container = await pumpRoom(tester, state: votingState);

      await newState(tester, container, matches: const ['m1', 'm2']);
      expect(find.byKey(const Key('match-celebration-m1')), findsOneWidget);

      await tester.pump(matchCelebrationDuration);
      await tester.pump();
      expect(find.byKey(const Key('match-celebration-m2')), findsOneWidget);

      await tester.pump(matchCelebrationDuration);
      await tester.pump();
      expect(find.text('È un match!'), findsNothing);
    });

    testWidgets('aKeyClosesTheSecondCelebrationWithoutVoting', (tester) async {
      final container = await pumpRoom(tester, state: votingState);
      await newState(tester, container, matches: const ['m1', 'm2']);
      await tester.pump(matchCelebrationDuration);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('match-celebration-m2')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(find.byKey(const Key('match-celebration-m2')), findsNothing);
      expect(match.calls.where((c) => c.startsWith('vote')), isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(match.calls, contains('vote r1 m1 yes'));
    });

    testWidgets('oldMatchesAreNotCelebratedWhenOpeningThePage', (tester) async {
      await pumpRoom(tester,
          state: testMatchState(
              phase: MatchPhase.voting,
              members: const [mario, luigi],
              stack: const ['m1', 'm2'],
              matches: const ['m1']));

      expect(find.text('È un match!'), findsNothing);
    });

    testWidgets('aMissingTitleIsVotedNo', (tester) async {
      library.itemsById.remove('m1');
      await pumpRoom(tester, state: votingState);
      await tester.pumpAndSettle();

      expect(match.calls, contains('vote r1 m1 no'));
      expect(find.text('Alien'), findsOneWidget);
    });

    testWidgets('allVotedWaitsForTheOthers', (tester) async {
      await pumpRoom(tester,
          state: testMatchState(
              phase: MatchPhase.voting,
              members: const [
                MatchMember(userId: 'u1', name: 'Mario', voted: 2),
                luigi,
              ],
              stack: const ['m1', 'm2']));

      expect(find.text('Hai votato tutto, aspetta gli altri'), findsOneWidget);
      expect(find.text('Altri 30 titoli'), findsNothing);
    });

    testWidgets('whenEveryoneHasFinishedTheCreatorGetsMore', (tester) async {
      await pumpRoom(tester,
          state: testMatchState(
              phase: MatchPhase.voting,
              members: const [
                MatchMember(userId: 'u1', name: 'Mario', voted: 2),
                MatchMember(userId: 'u2', name: 'Luigi', voted: 2),
              ],
              stack: const ['m1', 'm2']));

      await tester.tap(find.text('Altri 30 titoli'));
      await tester.pumpAndSettle();

      expect(match.calls, contains('more r1'));
    });

    testWidgets('aMemberDoesNotGetMore', (tester) async {
      await pumpRoom(tester,
          state: testMatchState(
              phase: MatchPhase.voting,
              creatorId: 'u2',
              creatorName: 'Luigi',
              members: const [
                MatchMember(userId: 'u1', name: 'Mario', voted: 2),
                MatchMember(userId: 'u2', name: 'Luigi', voted: 2),
              ],
              stack: const ['m1', 'm2']));

      expect(find.text('Altri 30 titoli'), findsNothing);
    });

    testWidgets('anEmptyStackSaysNoTitles', (tester) async {
      await pumpRoom(tester,
          state: testMatchState(
              phase: MatchPhase.voting, members: const [mario, luigi]));

      expect(find.text('Nessun titolo con questi filtri'), findsOneWidget);
      expect(find.text('Altri 30 titoli'), findsOneWidget);
    });

    testWidgets('startPartyNeedsAMatchAndUsesTheChosenFirst', (tester) async {
      final container = await pumpRoom(tester, state: votingState);
      expect(find.byKey(const Key('match-start-party')), findsNothing);

      match.rooms['r1'] = testMatchState(
          rev: 2,
          phase: MatchPhase.voting,
          members: const [mario, luigi],
          stack: const ['m1', 'm2'],
          matches: const ['m1', 'm2']);
      await container.read(matchRoomProvider.notifier).reload();
      await tester.pump();
      await tester.pump(matchCelebrationDuration);
      await tester.pump(matchCelebrationDuration);
      await tester.pump();

      await tester.tap(find.byKey(const Key('match-column-m2')));
      await tester.pump();
      expect(find.text('Parte per primo'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('match-start-party')));
      final gate = library.itemsByIdsGate = Completer<void>();
      await tester.tap(find.byKey(const Key('match-start-party')));
      await tester.pump();
      expect(
          tester
              .widget<WfButton>(find.byKey(const Key('match-start-party')))
              .onPressed,
          isNull,
          reason: 'spento mentre parte');
      gate.complete();
      await tester.pumpAndSettle();

      expect(syncPlay.queues.single.itemIds, ['m2', 'm1']);
      expect(match.calls, contains('party r1 g1'));
      await container.read(watchPartySessionProvider.notifier).leave();
      await tester.pump();
    });

    Future<ProviderContainer> closeWithParty(WidgetTester tester) async {
      final container = await pumpRoom(tester,
          state: testMatchState(
              phase: MatchPhase.voting,
              creatorId: 'u2',
              creatorName: 'Luigi',
              members: const [luigi, mario],
              stack: const ['m1', 'm2']));
      match.rooms['r1'] = testMatchState(
          rev: 2,
          phase: MatchPhase.closed,
          creatorId: 'u2',
          creatorName: 'Luigi',
          closedReason: MatchClosedReason.partyStarted,
          partyGroupId: 'g1');
      await container.read(matchRoomProvider.notifier).reload();
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('membersJoinThePartyByThemselves', (tester) async {
      final container = await closeWithParty(tester);

      expect(syncPlay.calls, contains('join g1'));
      expect(find.byType(MatchScreen), findsNothing);
      expect(find.text('Sala chiusa'), findsNothing);
      await container.read(watchPartySessionProvider.notifier).leave();
      await tester.pump();
    });

    testWidgets('aMemberWhoCannotJoinStillLeavesThePage', (tester) async {
      syncPlay.error = Exception('no');
      await closeWithParty(tester);

      expect(syncPlay.calls, contains('join g1'));
      expect(find.byType(MatchScreen), findsNothing);
      expect(find.text('Sala chiusa'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
