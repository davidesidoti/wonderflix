import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/features/match/match_seats.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<void> pumpSeats(WidgetTester tester, MatchState state,
          {Size size = const Size(1440, 900)}) =>
      pumpApp(
          tester,
          Scaffold(
              body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: MatchSeats(
                      state: state,
                      votedOf: (m) => m.userId == 'u1' ? 5 : m.voted))),
          surfaceSize: size);

  testWidgets('waitingShowsAllEightSeats', (tester) async {
    await pumpSeats(tester, testMatchState());

    expect(find.byKey(const ValueKey('match-seat-u1')), findsOneWidget);
    expect(find.text('libero'), findsNWidgets(matchMaxMembers - 1));
    expect(find.text('In sala, 1 su 8'), findsOneWidget);
  });

  testWidgets('votingShowsOnlyTakenSeatsWithProgress', (tester) async {
    await pumpSeats(
        tester,
        testMatchState(
            phase: MatchPhase.voting,
            stack: List.generate(30, (i) => 'm$i'),
            members: const [
              MatchMember(userId: 'u1', name: 'Mario', voted: 12),
              MatchMember(userId: 'u2', name: 'Sara', voted: 30),
            ]));

    expect(find.text('libero'), findsNothing);
    expect(find.textContaining('In sala'), findsNothing);
    // Il mio posto mostra il conteggio ottimistico, non quello del server.
    expect(find.text('5 su 30'), findsOneWidget);
    expect(find.text('finito'), findsOneWidget);
    expect(
        tester
            .widget<FractionallySizedBox>(
                find.byKey(const ValueKey('match-seat-fill-u1')))
            .widthFactor,
        closeTo(5 / 30, 1e-9));
    expect(
        tester
            .widget<FractionallySizedBox>(
                find.byKey(const ValueKey('match-seat-fill-u2')))
            .widthFactor,
        1.0);
  });

  testWidgets('longNamesWrapWithoutOverflowOnNarrowScreens', (tester) async {
    await pumpSeats(
        tester,
        testMatchState(members: [
          for (var i = 0; i < matchMaxMembers; i++)
            MatchMember(
                userId: 'u$i',
                name: 'un.nome.molto.molto.lungo.numero.$i',
                voted: 0),
        ]),
        size: const Size(390, 780));

    expect(tester.takeException(), isNull);
    expect(find.text('libero'), findsNothing);
    final tops = {
      for (var i = 0; i < matchMaxMembers; i++)
        tester.getTopLeft(find.byKey(ValueKey('match-seat-u$i'))).dy
    };
    expect(tops.length, greaterThan(1));
  });
}
