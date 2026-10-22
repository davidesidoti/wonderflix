import 'package:flutter/gestures.dart';
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

  /// Tratto dell'intro in cui il pulsante si vede: da 10 s a 89 s.
  const introOffer = 79;

  Future<FakeVideoEngine> pumpSkip(WidgetTester tester,
      {VoidCallback? onSkip, MotionLevel motion = MotionLevel.reduced}) async {
    final engine = FakeVideoEngine();
    await pumpApp(
      tester,
      Scaffold(
        // Ancorato a destra, come nel player.
        body: Stack(
          children: [
            Positioned(
              right: 32,
              bottom: 150,
              child: SkipSegmentButton(
                  engine: engine,
                  segments: segments,
                  onSkip: onSkip ?? () {}),
            ),
          ],
        ),
      ),
      motion: motion,
    );
    return engine;
  }

  double lineFactor(WidgetTester tester) => tester
      .widget<FractionallySizedBox>(find.byKey(const Key('skip-line')))
      .widthFactor!;

  Rect buttonRect(WidgetTester tester, String label) => tester.getRect(
      find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton)));

  testWidgets('intro: pulsante e linea che si accorcia; clic salta',
      (tester) async {
    var skipped = 0;
    final engine = await pumpSkip(tester, onSkip: () => skipped++);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Salta intro'), findsOneWidget);
    expect(lineFactor(tester), closeTo(69 / introOffer, 0.001));

    engine.emitPosition(const Duration(seconds: 50));
    await tester.pump();
    await tester.pump();
    expect(lineFactor(tester), closeTo(39 / introOffer, 0.001));

    await tester.tap(find.text('Salta intro'));
    expect(skipped, 1);

    engine.emitPosition(const Duration(seconds: 95));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Salta intro'), findsNothing);
  });

  testWidgets('la linea arriva a zero quando il pulsante se ne va',
      (tester) async {
    final engine = await pumpSkip(tester);
    engine.emitPosition(const Duration(seconds: 50));
    await tester.pump();
    await tester.pumpAndSettle();
    engine.emitPosition(const Duration(seconds: 88, milliseconds: 950));
    await tester.pump();
    await tester.pump();
    expect(find.text('Salta intro'), findsOneWidget);
    expect(lineFactor(tester), closeTo(0, 0.001));

    engine.emitPosition(const Duration(seconds: 89));
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

  testWidgets('riassunto → intro: i bordi destri restano allineati',
      (tester) async {
    final engine = await pumpSkip(tester);
    engine.emitPosition(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpAndSettle();
    final recap = buttonRect(tester, 'Salta riassunto');

    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Nella dissolvenza incrociata ci sono tutti e due, con lo stesso bordo
    // destro (quello del loro posto); il nuovo è più stretto.
    final intro = buttonRect(tester, 'Salta intro');
    expect(find.text('Salta riassunto'), findsOneWidget);
    expect(buttonRect(tester, 'Salta riassunto').right,
        closeTo(recap.right, 0.01));
    expect(intro.right, closeTo(recap.right, 0.01));
    expect(intro.width, lessThan(recap.width));

    await tester.pumpAndSettle();
    expect(find.text('Salta riassunto'), findsNothing);
    expect(buttonRect(tester, 'Salta intro').right, closeTo(recap.right, 0.01),
        reason: 'uscito il vecchio, il nuovo non salta');
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

  testWidgets('animazioni ridotte: entra solo sfumando', (tester) async {
    final engine = await pumpSkip(tester);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Salta intro'), findsOneWidget);
    expect(find.byKey(const Key('skip-enter')), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('uscita: parte piano e accelera', (tester) async {
    final engine = await pumpSkip(tester);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pumpAndSettle();
    engine.emitPosition(const Duration(seconds: 95));
    await tester.pump(); // arriva la posizione
    await tester.pump(); // parte l'uscita
    // Al 10% dell'uscita è ancora quasi opaco (al contrario, `accelerate`
    // sarebbe già sotto l'85%).
    await tester.pump(WfMotion.fast * 0.1);
    final fade = tester.widget<FadeTransition>(find
        .descendant(
            of: find.byType(SkipSegmentButton),
            matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, greaterThan(0.9));
    await tester.pumpAndSettle();
  });

  testWidgets('la linea segue la scala del pulsante al passaggio del mouse',
      (tester) async {
    final engine = await pumpSkip(tester, motion: MotionLevel.full);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Salta intro')));
    await tester.pumpAndSettle();

    final button = buttonRect(tester, 'Salta intro');
    final line = tester.getRect(find.byKey(const Key('skip-line')));
    final scale = tester
        .widget<AnimatedScale>(find
            .ancestor(
                of: find.text('Salta intro'),
                matching: find.byType(AnimatedScale))
            .first)
        .scale;
    expect(scale, greaterThan(1));
    // Stesso bordo sinistro e stessa base del pulsante ingrandito, e la
    // stessa parte della sua larghezza.
    expect(line.left, closeTo(button.left, 0.01));
    expect(line.bottom, closeTo(button.bottom, 0.01));
    expect(line.width, closeTo(button.width * lineFactor(tester), 0.01));
    expect(line.right, lessThanOrEqualTo(button.right + 0.01));
  });
}
