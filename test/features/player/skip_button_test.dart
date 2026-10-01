import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/skip_button.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  const segments = [
    MediaSegment(
        type: MediaSegmentType.recap,
        start: Duration.zero,
        end: Duration(seconds: 10)),
    MediaSegment(
        type: MediaSegmentType.intro,
        start: Duration(seconds: 10),
        end: Duration(seconds: 90)),
  ];

  Future<FakeVideoEngine> pumpSkip(WidgetTester tester,
      {VoidCallback? onSkip, MotionLevel motion = MotionLevel.reduced}) async {
    final engine = FakeVideoEngine();
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: SkipSegmentButton(
              engine: engine, segments: segments, onSkip: onSkip ?? () {}),
        ),
      ),
      motion: motion,
    );
    return engine;
  }

  double lineFactor(WidgetTester tester) => tester
      .widget<FractionallySizedBox>(find.byKey(const Key('skip-line')))
      .widthFactor!;

  testWidgets('intro: pulsante e linea che si accorcia; clic salta',
      (tester) async {
    var skipped = 0;
    final engine = await pumpSkip(tester, onSkip: () => skipped++);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Salta intro'), findsOneWidget);
    expect(lineFactor(tester), closeTo(70 / 80, 0.01));

    engine.emitPosition(const Duration(seconds: 50));
    await tester.pump();
    await tester.pump();
    expect(lineFactor(tester), closeTo(40 / 80, 0.01));

    await tester.tap(find.text('Salta intro'));
    expect(skipped, 1);

    engine.emitPosition(const Duration(seconds: 95));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Salta intro'), findsNothing);
  });

  testWidgets('riassunto: "Salta riassunto"', (tester) async {
    final engine = await pumpSkip(tester);
    engine.emitPosition(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Salta riassunto'), findsOneWidget);
  });

  testWidgets('animazioni complete: entra da destra', (tester) async {
    final engine = await pumpSkip(tester, motion: MotionLevel.full);
    // A 0 s c'è il riassunto: si parte da fuori dai segmenti, così nel
    // cambio non resta il pulsante precedente (con lo stesso `Transform`).
    engine.emitPosition(const Duration(seconds: 95));
    await tester.pump();
    await tester.pumpAndSettle();
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Per chiave: dentro `WfButton` c'è anche il `Transform` della scala.
    final shift = tester
        .widget<Transform>(find.byKey(const Key('skip-enter')))
        .transform
        .getTranslation()
        .x;
    expect(shift, greaterThan(0));
    await tester.pumpAndSettle();
  });
}
