import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/ui/remote_image_card.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('locandina: immagine, titolo, sottotitolo, etichetta e clic',
      (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Center(
        child: RemoteImageCard(
          shape: RemoteCardShape.poster,
          image: const ImageRef('https://image.tmdb.org/t/p/w342/p.jpg'),
          title: 'Hope',
          subtitle: 'Digitale · 13 ott',
          badge: const Text('In attesa'),
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('Hope'), findsOneWidget);
    expect(find.text('Digitale · 13 ott'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);
    expect(tester.widget<WfImage>(find.byType(WfImage)).image?.url,
        'https://image.tmdb.org/t/p/w342/p.jpg');
    expect(tester.getSize(find.byType(RemoteImageCard)).width,
        RemoteCardShape.poster.width);
    await tester.tap(find.text('Hope'));
    expect(taps, 1);
  });

  testWidgets('senza clic: niente cursore a mano', (tester) async {
    await pumpApp(
      tester,
      const Center(
        child: RemoteImageCard(
            shape: RemoteCardShape.landscape, image: null, title: 'Andor'),
      ),
    );
    expect(tester.getSize(find.byType(RemoteImageCard)).width,
        RemoteCardShape.landscape.width);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Andor')));
    addTearDown(gesture.removePointer);
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        isNot(SystemMouseCursors.click));
  });

  testWidgets('un clic che sparisce toglie anche il bordo dorato',
      (tester) async {
    final onTap = ValueNotifier<VoidCallback?>(() {});
    addTearDown(onTap.dispose);
    await pumpApp(
      tester,
      Center(
        child: ValueListenableBuilder<VoidCallback?>(
          valueListenable: onTap,
          builder: (context, tap, _) => RemoteImageCard(
              shape: RemoteCardShape.poster,
              image: null,
              title: 'Hope',
              onTap: tap),
        ),
      ),
    );
    Color borderColor() {
      final decoration =
          tester.widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .decoration! as BoxDecoration;
      return (decoration.border! as Border).top.color;
    }

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Hope')));
    addTearDown(gesture.removePointer);
    await tester.pump();
    expect(borderColor(), WfColors.gold, reason: 'col mouse sopra, cliccabile');

    // Il MouseRegion se ne va e onExit non arriva mai.
    onTap.value = null;
    await tester.pump();
    expect(borderColor(), Colors.transparent);
  });
}
