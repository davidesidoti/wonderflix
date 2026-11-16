import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/features/match/match_column.dart';
import 'package:wonderflix/features/match/match_ticket.dart';

import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final titles = {
    'm1': testItem(id: 'm1', name: 'Dune'),
    'm2': testItem(id: 'm2', name: 'Alien'),
    'm3': testItem(id: 'm3', name: 'Heat'),
  };

  Future<void> pumpColumn(
    WidgetTester tester,
    MatchState state, {
    String? chosen,
    ValueChanged<String>? onChoose,
    VoidCallback? onStartParty,
    Size surfaceSize = const Size(1440, 900),
  }) {
    return pumpApp(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: MatchColumn(
            state: state,
            titles: titles,
            chosen: chosen,
            onChoose: onChoose,
            onStartParty: onStartParty,
          ),
        ),
      ),
      surfaceSize: surfaceSize,
    );
  }

  final withNear = testMatchState(
    matches: const ['m2', 'm1'],
    nearMatches: const [MatchNearMatch(itemId: 'm3', yes: 1, of: 2)],
  );

  testWidgets('matchesInOrderAndNearMatchesWithCounts', (tester) async {
    await pumpColumn(tester, withNear);

    expect(find.text('Piaciuti a tutti'), findsOneWidget);
    expect(find.text('2 match'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Alien')).dy,
      lessThan(tester.getTopLeft(find.text('Dune')).dy),
    );
    expect(find.text('Piaciuti a quasi tutti'), findsOneWidget);
    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('1 sì su 2'), findsOneWidget);
    expect(find.byType(MatchTicket), findsNWidgets(3));
  });

  testWidgets('emptySaysNoMatches', (tester) async {
    await pumpColumn(tester, testMatchState());

    expect(find.text('Ancora nessun match'), findsOneWidget);
    expect(find.text('Piaciuti a quasi tutti'), findsNothing);
    expect(find.byKey(const Key('match-start-party')), findsNothing);
  });

  testWidgets('ilPrimoParteSeNessunoNeHaSceltoUnAltro', (tester) async {
    final chosen = <String>[];
    await pumpColumn(tester, withNear, onChoose: chosen.add);
    expect(
      find.descendant(
        of: find.byKey(const Key('match-column-m2')),
        matching: find.text('Parte per primo'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('match-column-m1')));
    expect(chosen, ['m1']);

    await pumpColumn(tester, withNear, chosen: 'm1', onChoose: chosen.add);
    expect(
      find.descendant(
        of: find.byKey(const Key('match-column-m1')),
        matching: find.text('Parte per primo'),
      ),
      findsOneWidget,
    );
    expect(find.text('Parte per primo'), findsOneWidget);
  });

  testWidgets('ilPulsanteContaIMatchEIlQuasiMatchScelto', (tester) async {
    await pumpColumn(tester, withNear, onChoose: (_) {}, onStartParty: () {});
    expect(find.text('Avvia il party con 2 titoli'), findsOneWidget);

    await pumpColumn(
      tester,
      withNear,
      chosen: 'm3',
      onChoose: (_) {},
      onStartParty: () {},
    );
    expect(find.text('Avvia il party con 3 titoli'), findsOneWidget);

    await pumpColumn(
      tester,
      testMatchState(matches: const ['m1']),
      onChoose: (_) {},
      onStartParty: () {},
    );
    expect(find.text('Avvia il party con 1 titolo'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('match-start-party'))),
      const Size(360, 44),
    );
  });

  testWidgets('withoutOnChooseNothingIsClickable', (tester) async {
    await pumpColumn(tester, withNear);

    expect(
      find.descendant(
        of: find.byKey(const Key('match-column-m3')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(find.text('Parte per primo'), findsNothing);
    expect(find.byKey(const Key('match-start-party')), findsNothing);
  });

  testWidgets('nelloStrettoIBigliettiStannoInFila', (tester) async {
    await pumpColumn(
      tester,
      withNear,
      onChoose: (_) {},
      onStartParty: () {},
      surfaceSize: const Size(390, 780),
    );

    final alien = tester.getRect(find.byKey(const Key('match-column-m2')));
    final dune = tester.getRect(find.byKey(const Key('match-column-m1')));
    expect(alien.width, 250);
    expect(dune.top, alien.top);
    expect(dune.left, greaterThan(alien.right));
    expect(tester.takeException(), isNull);
  });
}
