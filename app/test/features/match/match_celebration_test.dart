import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/match/match_celebration.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  var done = 0;

  setUp(() => done = 0);

  Future<void> pumpIt(WidgetTester tester,
          {MotionLevel motion = MotionLevel.reduced, bool item = true}) =>
      pumpApp(
          tester,
          Scaffold(
              body: MatchCelebration(
                  id: 'm1',
                  item: item ? testItem(id: 'm1', name: 'Dune') : null,
                  onDone: () => done++)),
          motion: motion);

  final ticket = find.byKey(const Key('match-celebration-ticket'));

  testWidgets('biglietto con locandina, nome e "Piace a tutti"',
      (tester) async {
    await pumpIt(tester);

    expect(tester.getSize(ticket).width, 260);
    expect(find.descendant(of: ticket, matching: find.text('Dune')),
        findsOneWidget);
    expect(find.text('Piace a tutti'), findsOneWidget);
    final title = tester.widget<Text>(find.text('È un match!'));
    expect(title.style?.fontSize, 64);
  });

  testWidgets('con le animazioni ridotte compare senza ingrandirsi',
      (tester) async {
    await pumpIt(tester);
    expect(tester.getRect(ticket).width, 260);
  });

  testWidgets('con le animazioni piene entra ingrandendosi', (tester) async {
    await pumpIt(tester, motion: MotionLevel.full);
    expect(tester.getRect(ticket).width, isNot(closeTo(260, 1)));

    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(ticket).width, closeTo(260, 0.5));
    await tester.pump(matchCelebrationDuration);
  });

  testWidgets('senza titolo resta il testo, senza eccezioni', (tester) async {
    await pumpIt(tester, item: false);

    expect(tester.takeException(), isNull);
    expect(find.text('È un match!'), findsOneWidget);
    expect(ticket, findsNothing);
  });

  testWidgets('itGoesAwayAfterTwoSeconds', (tester) async {
    await pumpIt(tester);
    expect(find.text('È un match!'), findsOneWidget);

    await tester.pump(matchCelebrationDuration - const Duration(milliseconds: 1));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 1));

    expect(done, 1);
  });

  testWidgets('aTapOrKeyClosesItEarlier', (tester) async {
    await pumpIt(tester);
    await tester.tap(find.text('È un match!'));
    expect(done, 1);
    await tester.pump(matchCelebrationDuration);
    expect(done, 1);
  });

  testWidgets('aKeyClosesItEarlier', (tester) async {
    await pumpIt(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(done, 1);

    // Il timer non fa scattare una seconda chiusura.
    await tester.pump(matchCelebrationDuration);
    expect(done, 1);
  });
}
