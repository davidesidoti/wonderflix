import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/watch_party/party_waiting_overlay.dart';

import '../../support/pump_app.dart';

void main() {
  Future<ValueNotifier<bool>> pumpWaiting(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final waiting = ValueNotifier(false);
    addTearDown(waiting.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: waiting,
          builder: (context, value, _) =>
              PartyWaitingOverlay(waiting: value, onResume: () {}),
        ),
      ),
      motion: motion,
    );
    return waiting;
  }

  testWidgets('dopo 1 s sfuma dentro; finita l\'attesa sfuma via',
      (tester) async {
    final waiting = await pumpWaiting(tester);
    waiting.value = true;
    await tester.pump();
    await tester.pump(PartyWaitingOverlay.delay);
    await tester.pump();
    expect(find.text('In attesa degli altri membri…'), findsOneWidget);
    double opacity() => tester
        .widget<Opacity>(find.byKey(const Key('party-waiting')))
        .opacity;
    expect(opacity(), lessThan(1), reason: 'sta entrando');
    await tester.pumpAndSettle();
    expect(opacity(), 1);

    waiting.value = false;
    await tester.pump();
    expect(find.text('In attesa degli altri membri…'), findsOneWidget,
        reason: 'resta mentre sfuma');
    await tester.pumpAndSettle();
    expect(find.text('In attesa degli altri membri…'), findsNothing);
  });

  testWidgets('animazioni complete: la clessidra si gira', (tester) async {
    final waiting = await pumpWaiting(tester, motion: MotionLevel.full);
    waiting.value = true;
    await tester.pump();
    await tester.pump(PartyWaitingOverlay.delay);
    await tester.pump();
    double angle() => tester
        .widget<Transform>(find.byKey(const Key('waiting-hourglass')))
        .transform
        .getRotation()
        .entry(1, 0);
    expect(angle(), 0);
    await tester.pump(hourglassPeriod * 0.85);
    expect(angle(), isNot(0));
    // Clessidra e puntini girano: niente pumpAndSettle.
    waiting.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(); // `onEnd` la toglie dall'albero
    expect(find.byKey(const Key('waiting-hourglass')), findsNothing);
  });

  testWidgets('animazioni ridotte: clessidra ferma', (tester) async {
    final waiting = await pumpWaiting(tester);
    waiting.value = true;
    await tester.pump();
    await tester.pump(PartyWaitingOverlay.delay);
    await tester.pumpAndSettle();
    await tester.pump(hourglassPeriod * 0.85);
    expect(
        tester
            .widget<Transform>(find.byKey(const Key('waiting-hourglass')))
            .transform
            .getRotation()
            .entry(1, 0),
        0);
  });
}
