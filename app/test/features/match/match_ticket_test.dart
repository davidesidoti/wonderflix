import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/match/match_ticket.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<void> pumpTicket(WidgetTester tester, MatchTicket ticket) =>
      pumpApp(tester, Scaffold(body: Center(child: ticket)));

  testWidgets('senza titolo: nessuna eccezione e nome vuoto', (tester) async {
    await pumpTicket(
      tester,
      const MatchTicket(id: 'x', item: null, chosen: false),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MatchTicket)), const Size(360, 84));
  });

  testWidgets('film: "Film · 1h 49m"', (tester) async {
    await pumpTicket(
      tester,
      MatchTicket(
        id: 'm1',
        item: testItem(id: 'm1', name: 'The Wrestler', runtimeMinutes: 109),
        chosen: false,
      ),
    );

    expect(find.text('The Wrestler'), findsOneWidget);
    expect(find.text('Film · 1h 49m'), findsOneWidget);
  });

  testWidgets('serie: "Serie · 1 stagione"', (tester) async {
    await pumpTicket(
      tester,
      MatchTicket(
        id: 's1',
        item: testItem(
          id: 's1',
          name: 'Osiris',
          kind: ItemKind.series,
          childCount: 1,
        ),
        chosen: false,
      ),
    );

    expect(find.text('Serie · 1 stagione'), findsOneWidget);
  });

  testWidgets('scelto: "Parte per primo" in oro al posto della riga', (
    tester,
  ) async {
    await pumpTicket(
      tester,
      MatchTicket(
        id: 'm1',
        item: testItem(id: 'm1', name: 'Dune'),
        chosen: true,
        note: '1 sì su 2',
      ),
    );

    final first = tester.widget<Text>(find.text('Parte per primo'));
    expect(first.style?.color, WfColors.gold);
    expect(find.text('1 sì su 2'), findsNothing);
  });

  testWidgets('la nota prende il posto della riga', (tester) async {
    await pumpTicket(
      tester,
      MatchTicket(
        id: 'm1',
        item: testItem(id: 'm1', name: 'Dune'),
        chosen: false,
        note: '1 sì su 2',
      ),
    );

    expect(find.text('1 sì su 2'), findsOneWidget);
    expect(find.textContaining('Film'), findsNothing);
  });

  testWidgets('stretto: fondale da 104', (tester) async {
    await pumpTicket(
      tester,
      MatchTicket(
        id: 'm1',
        item: testItem(id: 'm1'),
        chosen: false,
        width: 250,
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('match-ticket-image'))).width,
      104,
    );
  });
}
