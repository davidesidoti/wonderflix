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
  });
}
