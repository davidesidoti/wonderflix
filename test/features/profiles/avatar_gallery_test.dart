import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/profiles/avatar_gallery.dart';

/// Un intero a 32 bit big-endian (l'intestazione IHDR di un PNG).
int _uint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

void main() {
  test('24 avatar, icone tutte diverse, colori diversi da quelli vicini', () {
    expect(galleryGradients, hasLength(8));
    expect(galleryAvatars, hasLength(24));
    expect(galleryAvatars.map((avatar) => avatar.icon).toSet(), hasLength(24));
    for (var i = 1; i < galleryAvatars.length; i++) {
      expect(galleryAvatars[i].colors, isNot(galleryAvatars[i - 1].colors));
    }
  });

  testWidgets('ogni avatar è un PNG di 512×512', (tester) async {
    final pngs = await tester
        .runAsync(() => Future.wait(galleryAvatars.map(renderGalleryAvatar)));

    for (final png in pngs!) {
      expect(String.fromCharCodes(png.sublist(1, 4)), 'PNG');
      expect(_uint32(png, 16), galleryAvatarSize);
      expect(_uint32(png, 20), galleryAvatarSize);
    }
  });

  testWidgets('l\'anteprima ha il suo lato', (tester) async {
    await tester.pumpWidget(Center(
        child: GalleryAvatarView(avatar: galleryAvatars.first, size: 64)));

    expect(tester.getSize(find.byType(GalleryAvatarView)), const Size(64, 64));
  });
}
