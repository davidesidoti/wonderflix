import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/page_transitions.dart';

void main() {
  /// Prodotto delle opacità sopra il testo 'pagina'.
  double opacityOf(WidgetTester tester) => tester
      .widgetList<FadeTransition>(find.ancestor(
          of: find.text('pagina'), matching: find.byType(FadeTransition)))
      .fold(1.0, (value, fade) => value * fade.opacity.value);

  Future<void> pumpTransition(WidgetTester tester, MotionLevel level,
      double animation, double secondary) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: pageTransition(
        WfMotion(level),
        AlwaysStoppedAnimation(animation),
        AlwaysStoppedAnimation(secondary),
        const Text('pagina'),
      ),
    ));
  }

  testWidgets('completa: entra dopo che la vecchia è uscita', (tester) async {
    await pumpTransition(tester, MotionLevel.full, 0.2, 0);
    expect(opacityOf(tester), 0);
    await pumpTransition(tester, MotionLevel.full, 1, 0);
    expect(opacityOf(tester), 1);
    final scale = tester.widget<ScaleTransition>(find.ancestor(
        of: find.text('pagina'), matching: find.byType(ScaleTransition)));
    expect(scale.scale.value, 1);
  });

  testWidgets('completa: esce quando un\'altra pagina entra sopra',
      (tester) async {
    await pumpTransition(tester, MotionLevel.full, 1, 0.5);
    expect(opacityOf(tester), 0);
  });

  testWidgets('ridotta: sola dissolvenza lineare', (tester) async {
    await pumpTransition(tester, MotionLevel.reduced, 0.5, 0);
    expect(opacityOf(tester), 0.5);
    expect(find.byType(ScaleTransition), findsNothing);
  });
}
