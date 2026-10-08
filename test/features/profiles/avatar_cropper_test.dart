import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wonderflix/features/profiles/avatar_cropper.dart';
import 'package:wonderflix/features/profiles/avatar_image.dart';

import '../../support/pump_app.dart';

void main() {
  const image = Size(400, 200);

  test('i conti del ritaglio', () {
    expect(cropBaseScale(image, 200), 1.0);
    expect(centeredCropOffset(image, 200), const Offset(-100, 0));
    expect(initialCropArea(image, 200), const CropArea(100, 0, 200));
    // Due volte più grande: il riquadro è la metà.
    expect(cropAreaFor(image, 200, 2, const Offset(-200, -100)),
        const CropArea(100, 50, 100));
  });

  test('l\'immagine copre sempre il riquadro', () {
    expect(clampCropOffset(const Offset(50, 20), image, 200, 1), Offset.zero);
    expect(clampCropOffset(const Offset(-500, -20), image, 200, 1),
        const Offset(-200, 0));
    expect(clampCropOffset(const Offset(-1000, -1000), image, 200, 2),
        const Offset(-600, -200));
  });

  testWidgets('trascinare, il cursore e la rotella', (tester) async {
    final areas = <CropArea>[];
    final working = WorkingImage(
        img.encodePng(img.Image(width: 4, height: 2)), 400, 200);
    // Il cursore vuole un Material sopra (nella finestra c'è già).
    await pumpApp(
        tester,
        Material(
          child: Center(
              child: AvatarCropper(
                  image: working, viewport: 200, onChanged: areas.add)),
        ));

    // Trascinata verso destra oltre il bordo: si ferma al bordo sinistro.
    await tester.drag(
        find.byKey(const Key('avatar-crop-area')), const Offset(300, 0));
    await tester.pump();
    expect(areas.last, const CropArea(0, 0, 200));

    // Il cursore in fondo: 4×.
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pump();
    expect(areas.last.side, 50);

    // La rotella verso il basso rimpicciolisce di uno scatto.
    final center = tester.getCenter(find.byKey(const Key('avatar-crop-area')));
    await tester.sendEventToBinding(PointerScrollEvent(
        position: center, scrollDelta: const Offset(0, 20)));
    await tester.pump();
    expect(areas.last.side, closeTo(55, 0.01));
  });
}
