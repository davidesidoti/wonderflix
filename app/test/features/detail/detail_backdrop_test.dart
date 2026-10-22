import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/detail/detail_backdrop.dart';
import 'package:wonderflix/features/detail/detail_header.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<ScrollController> pumpBackdrop(WidgetTester tester,
      {required MotionLevel motion}) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: detailHeaderHeight,
              child: DetailBackdrop(
                  item: testItem(id: 'm1', name: 'Dune'),
                  launch: null,
                  controller: controller),
            ),
            Positioned.fill(
              child: ListView(
                controller: controller,
                children: const [SizedBox(height: 4000)],
              ),
            ),
          ],
        ),
      ),
      motion: motion,
    );
    return controller;
  }

  /// Traslazione verticale dello sfondo.
  double shift(WidgetTester tester) {
    final transform = tester.widget<Transform>(find
        .descendant(
            of: find.byType(DetailBackdrop), matching: find.byType(Transform))
        .first);
    return transform.transform.getTranslation().y;
  }

  /// Altezza visibile dello sfondo (ritaglio).
  double clipHeight(WidgetTester tester) {
    final clip = tester.renderObject<RenderClipRect>(find
        .descendant(
            of: find.byType(DetailBackdrop), matching: find.byType(ClipRect))
        .first);
    return clip.clipper!.getClip(clip.size).height;
  }

  testWidgets('parallasse: lo sfondo sale a metà velocità e si ritaglia '
      'alla testata visibile', (tester) async {
    final controller = await pumpBackdrop(tester, motion: MotionLevel.full);
    expect(shift(tester), 0);
    expect(clipHeight(tester), detailHeaderHeight);
    controller.jumpTo(200);
    await tester.pump();
    expect(shift(tester), -100);
    expect(clipHeight(tester), detailHeaderHeight - 200);
  });

  testWidgets('animazioni ridotte: lo sfondo segue lo scroll', (tester) async {
    final controller = await pumpBackdrop(tester, motion: MotionLevel.reduced);
    controller.jumpTo(200);
    await tester.pump();
    expect(shift(tester), -200);
  });
}
