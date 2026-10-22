import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/features/match/match_column.dart';

import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final titles = {
    'm1': testItem(id: 'm1', name: 'Dune'),
    'm2': testItem(id: 'm2', name: 'Alien'),
    'm3': testItem(id: 'm3', name: 'Heat'),
  };

  Future<void> pumpColumn(WidgetTester tester, MatchState state,
      {String? chosen, ValueChanged<String>? onChoose}) {
    return pumpApp(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: MatchColumn(
                    state: state,
                    titles: titles,
                    chosen: chosen,
                    onChoose: onChoose))));
  }

  final withNear = testMatchState(
      matches: const ['m2', 'm1'],
      nearMatches: const [MatchNearMatch(itemId: 'm3', yes: 1, of: 2)]);

  testWidgets('matchesInOrderAndNearMatchesWithCounts', (tester) async {
    await pumpColumn(tester, withNear);

    expect(find.text('Match'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Alien')).dy,
        lessThan(tester.getTopLeft(find.text('Dune')).dy));
    expect(find.text('Piaciuti a quasi tutti'), findsOneWidget);
    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('1 su 2'), findsOneWidget);
  });

  testWidgets('emptySaysNoMatches', (tester) async {
    await pumpColumn(tester, testMatchState());

    expect(find.text('Ancora nessun match'), findsOneWidget);
    expect(find.text('Piaciuti a quasi tutti'), findsNothing);
  });

  testWidgets('chooseMarksPlaysFirst', (tester) async {
    final chosen = <String>[];
    await pumpColumn(tester, withNear, onChoose: chosen.add);
    expect(find.text('Parte per primo'), findsNothing);

    await tester.tap(find.byKey(const Key('match-column-m3')));
    expect(chosen, ['m3']);

    await pumpColumn(tester, withNear, chosen: 'm3', onChoose: chosen.add);
    expect(find.text('Parte per primo'), findsOneWidget);
  });

  testWidgets('withoutOnChooseNothingIsClickable', (tester) async {
    await pumpColumn(tester, withNear);

    expect(
        find.descendant(
            of: find.byKey(const Key('match-column-m3')),
            matching: find.byType(InkWell)),
        findsNothing);
  });
}
