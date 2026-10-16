import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/match/match_celebration.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  var done = 0;

  setUp(() => done = 0);

  Future<void> pumpIt(WidgetTester tester) => pumpApp(
      tester,
      Scaffold(
          body: MatchCelebration(
              item: testItem(id: 'm1', name: 'Dune'), onDone: () => done++)));

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
