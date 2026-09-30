import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/shimmer.dart';
import 'package:wonderflix/ui/states.dart';

void main() {
  test('il gradiente copre tutta l\'onda, spostato del blocco', () {
    expect(shimmerShaderRect(const Size(800, 600), const Offset(120, 40)),
        const Rect.fromLTWH(-120, -40, 800, 600));
  });

  test('l\'onda accelera e rallenta (easeInOut), da sinistra a destra', () {
    expect(shimmerShift(0), -1);
    expect(shimmerShift(1), 1);
    expect(shimmerShift(0.5), closeTo(0, 1e-9));
    // Lineare sarebbe -0,5: all'inizio l'onda va più piano.
    expect(shimmerShift(0.25),
        closeTo(WfMotion.standard.transform(0.25) * 2 - 1, 1e-9));
    expect(shimmerShift(0.25), lessThan(-0.5));
  });

  Widget page(MotionLevel level) => Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: WfMotion(level),
          child: const WfShimmer(
            child: Column(children: [
              SkeletonBox(width: 200, height: 40),
              SizedBox(height: 20),
              SkeletonBox(width: 300, height: 60),
            ]),
          ),
        ),
      );

  testWidgets('completa: un solo controller anima tutti i blocchi',
      (tester) async {
    await tester.pumpWidget(page(MotionLevel.full));
    expect(find.byKey(shimmerPaintKey), findsNWidgets(2));
    expect(SchedulerBinding.instance.transientCallbackCount, 1);
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    // Via l'albero: il controller si ferma.
    await tester.pumpWidget(const SizedBox());
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('ridotta: blocchi fermi, nessuna animazione', (tester) async {
    await tester.pumpWidget(page(MotionLevel.reduced));
    expect(find.byKey(shimmerPaintKey), findsNothing);
    expect(find.byType(SkeletonBox), findsNWidgets(2));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('cambio di livello avanti e indietro: nessun errore',
      (tester) async {
    await tester.pumpWidget(page(MotionLevel.full));
    await tester.pumpWidget(page(MotionLevel.reduced));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    await tester.pumpWidget(page(MotionLevel.full));
    expect(tester.takeException(), isNull);
    expect(find.byKey(shimmerPaintKey), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SkeletonBox senza WfShimmer: fermo come prima', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: WfMotionScope(
        motion: WfMotion(MotionLevel.full),
        child: Center(child: SkeletonBox(width: 100, height: 20)),
      ),
    ));
    expect(find.byKey(shimmerPaintKey), findsNothing);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
