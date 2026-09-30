import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/startup/splash_screen.dart';

import '../../support/pump_app.dart';

// Lo spinner dello splash gira sempre: niente pumpAndSettle.
void main() {
  testWidgets('completa: il logo compare e il riflesso passa una volta',
      (tester) async {
    await pumpApp(tester, const SplashScreen(), motion: MotionLevel.full);
    final logo = find.byKey(const Key('splash-logo'));
    double opacity() => tester
        .widget<Opacity>(
            find.ancestor(of: logo, matching: find.byType(Opacity)).first)
        .opacity;
    expect(opacity(), lessThan(1));
    expect(find.byKey(const Key('splash-sheen')), findsOneWidget);
    await tester.pump(splashIntroDuration);
    await tester.pump();
    expect(opacity(), 1);
  });

  testWidgets('ridotta: logo fermo, nessun riflesso', (tester) async {
    await pumpApp(tester, const SplashScreen());
    expect(find.byKey(const Key('splash-sheen')), findsNothing);
    final fades = tester.widgetList<Opacity>(find.ancestor(
        of: find.byKey(const Key('splash-logo')),
        matching: find.byType(Opacity)));
    expect(fades.every((f) => f.opacity == 1), isTrue);
  });
}
