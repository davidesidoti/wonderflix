import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/ui/wf_image.dart';

const _hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

void main() {
  testWidgets('segnaposto: grigio del tema mentre decodifica, mai azzurro',
      (tester) async {
    await tester.pumpWidget(const ImagePlaceholder(blurHash: _hash));
    expect(tester.widget<BlurHash>(find.byType(BlurHash)).color,
        WfColors.surfaceHigh);
  });

  testWidgets('dentro TransparentPlaceholders il segnaposto è trasparente',
      (tester) async {
    await tester.pumpWidget(const TransparentPlaceholders(
      child: Column(children: [
        Expanded(child: ImagePlaceholder(blurHash: _hash)),
        Expanded(child: ImagePlaceholder(icon: Icons.movie)),
      ]),
    ));
    expect(find.byType(BlurHash), findsNothing);
    expect(find.byType(ColoredBox), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  // Nei test l'HttpClient risponde 400 a ogni richiesta.
  Widget web() => const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 40,
          height: 60,
          child: _Web(),
        ),
      );

  testWidgets('web: prima del caricamento si vede il blurhash', (tester) async {
    await tester.pumpWidget(web());
    expect(find.byType(BlurHash), findsOneWidget);
  });

  testWidgets('web: se il caricamento fallisce si vede l\'icona di errore',
      (tester) async {
    await tester.pumpWidget(web());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(LucideIcons.imageOff), findsOneWidget);
  });
}

class _Web extends StatelessWidget {
  const _Web();

  @override
  Widget build(BuildContext context) => webNetworkImage(
      const ImageRef('http://localhost/x.jpg', _hash), BoxFit.cover, 80);
}
