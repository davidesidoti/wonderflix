import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/ui/backdrop_image.dart';

import '../support/pump_app.dart';

void main() {
  const backdrop = ImageRef('https://x/backdrop');
  const poster = ImageRef('https://x/poster');

  testWidgets('con lo sfondo: nessuna sfocatura', (tester) async {
    await pumpApp(tester,
        const BackdropImage(backdrop: backdrop, fallback: poster));
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('senza sfondo: locandina sfocata', (tester) async {
    await pumpApp(tester, const BackdropImage(backdrop: null, fallback: poster));
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byIcon(LucideIcons.film), findsNothing);
    // La sfocatura disegna oltre i bordi: va ritagliata, altrimenti "sbava"
    // sulle sezioni sotto il banner.
    expect(
      find.ancestor(of: find.byType(ImageFiltered), matching: find.byType(ClipRect)),
      findsOneWidget,
    );
  });

  testWidgets('senza immagini: solo sfondo scuro, niente icona', (tester) async {
    await pumpApp(tester, const BackdropImage(backdrop: null, fallback: null));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byIcon(LucideIcons.film), findsNothing);
  });
}
