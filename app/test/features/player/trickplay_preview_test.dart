import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/trickplay.dart';
import 'package:wonderflix/features/player/trickplay_preview.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('ritaglia la cella del mosaico con l\'autenticazione',
      (tester) async {
    final urls = <String>[];
    await pumpApp(
      tester,
      const Center(
        child: TrickplayPreview(
          url: 'https://media.example.com/Videos/m1/Trickplay/320/3.jpg',
          info: TrickplayInfo(
            width: 320,
            height: 180,
            tileWidth: 10,
            tileHeight: 10,
            thumbnailCount: 700,
            interval: Duration(seconds: 10),
          ),
          tile: TrickplayTile(sheet: 3, column: 2, row: 6),
        ),
      ),
      overrides: [
        authImageProvider.overrideWithValue((url) {
          urls.add(url);
          return MemoryImage(Uint8List.fromList(transparentPng));
        }),
      ],
    );
    expect(urls, ['https://media.example.com/Videos/m1/Trickplay/320/3.jpg']);
    expect(tester.getSize(find.byType(TrickplayPreview)), const Size(240, 135));

    // Cella (2, 6) di 240×135: il mosaico si sposta di 2 celle a sinistra
    // e 6 in su.
    final translate = tester.widget<Transform>(find.descendant(
        of: find.byType(TrickplayPreview), matching: find.byType(Transform)));
    expect(translate.transform.getTranslation().x, -480);
    expect(translate.transform.getTranslation().y, -810);

    // Mosaico dimensionato solo in larghezza (l'ultimo può avere meno righe)
    // e decodificato alla dimensione mostrata.
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 2400);
    expect(image.height, isNull);
    expect(image.fit, BoxFit.fitWidth);
    expect(image.alignment, Alignment.topLeft);
    expect(image.gaplessPlayback, isFalse);
    expect(image.key, const ValueKey(
        'https://media.example.com/Videos/m1/Trickplay/320/3.jpg'));
    final resized = image.image as ResizeImage;
    expect(resized.width, (2400 * tester.view.devicePixelRatio).round());
    expect(resized.height, isNull);
  });

  testWidgets('dimensioni non valide: nessuna anteprima', (tester) async {
    await pumpApp(
      tester,
      const Center(
        child: TrickplayPreview(
          url: 'https://media.example.com/x.jpg',
          info: TrickplayInfo(
            width: 0,
            height: 0,
            tileWidth: 10,
            tileHeight: 10,
            thumbnailCount: 700,
            interval: Duration(seconds: 10),
          ),
          tile: TrickplayTile(sheet: 0, column: 0, row: 0),
        ),
      ),
      overrides: [
        authImageProvider.overrideWithValue(
            (url) => MemoryImage(Uint8List.fromList(transparentPng))),
      ],
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
