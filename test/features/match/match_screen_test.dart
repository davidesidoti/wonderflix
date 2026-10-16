import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/match/match_actions.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/match/match_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/tonight/tonight_controller.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeMatchApi match;
  late FakeSocialApi social;
  late SharedPreferences prefs;

  const mario = MatchMember(userId: 'u1', name: 'Mario', voted: 0);
  const luigi = MatchMember(userId: 'u2', name: 'Luigi', voted: 0);

  setUp(() async {
    match = FakeMatchApi();
    social = FakeSocialApi()
      ..snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true),
        testFriend('u3', 'Peach', online: true),
        testFriend('u4', 'Toad'),
      ]);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

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
          features: const SocialFeatures(friends: true, match: true)),
      matchApiProvider.overrideWithValue(match),
      sharedPreferencesProvider.overrideWithValue(prefs),
      libraryApiProvider.overrideWithValue(FakeLibraryApi()),
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
}
