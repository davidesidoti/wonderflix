import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_glow.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  Future<List<String>> pumpGlow(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final urls = <String>[];
    await pumpApp(
      tester,
      Scaffold(body: HomeGlow(item: testItem(id: 'Dune', name: 'Dune'))),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        imageBuilderProvider.overrideWithValue((image, fit) {
          urls.add(image.url);
          return const ColoredBox(color: Color(0xFF333333));
        }),
      ],
      motion: motion,
    );
    return urls;
  }

  testWidgets("l'alone: fondale piccolissimo, alto 640, opacità 0,28",
      (tester) async {
    final urls = await pumpGlow(tester);
    expect(urls.single, contains('Backdrop'));
    expect(urls.single, contains('maxWidth=32'));
    expect(tester.getSize(find.byType(HomeGlow)).height, 640);
    expect(
        tester
            .widget<Opacity>(find.descendant(
                of: find.byType(HomeGlow), matching: find.byType(Opacity)))
            .opacity,
        0.28);
    expect(
        find.descendant(
            of: find.byType(HomeGlow), matching: find.byType(ShaderMask)),
        findsOneWidget);
  });

  testWidgets('cambia in dissolvenza, senza con le animazioni ridotte',
      (tester) async {
    await pumpGlow(tester);
    expect(tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
        .duration, Duration.zero);
    await pumpGlow(tester, motion: MotionLevel.full);
    expect(tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
        .duration, WfMotion.crossfade);
  });
}
