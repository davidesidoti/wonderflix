import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wonderflix/features/profiles/avatar_image.dart';

Uint8List _png(int width, int height) =>
    img.encodePng(img.Image(width: width, height: height));

Matcher _fails(AvatarImageError reason) => throwsA(
    isA<AvatarImageException>().having((e) => e.reason, 'reason', reason));

void main() {
  group('preparazione', () {
    test('un PNG: stesso lato, in PNG', () {
      final working = prepareAvatarImageSync(_png(300, 200));

      expect((working.width, working.height), (300, 200));
      expect(img.decodePng(working.bytes)!.width, 300);
    });

    test('oltre 2048 px: ridotta', () {
      final working = prepareAvatarImageSync(_png(4096, 1024));

      expect((working.width, working.height), (maxWorkingSide, 512));
    });

    test('una foto girata: raddrizzata secondo l\'EXIF', () {
      final photo = img.Image(width: 300, height: 200);
      photo.exif.imageIfd.orientation = 6;

      final working = prepareAvatarImageSync(img.encodeJpg(photo));

      expect((working.width, working.height), (200, 300));
    });

    test('un file che non è un\'immagine: non valida', () {
      expect(() => prepareAvatarImageSync(Uint8List.fromList([1, 2, 3, 4])),
          _fails(AvatarImageError.invalid));
    });

    test('oltre 20 MB: troppo grande, senza decodificare', () {
      expect(() => prepareAvatarImageSync(Uint8List(maxAvatarFileBytes + 1)),
          _fails(AvatarImageError.tooLarge));
    });

    testWidgets('in un isolate', (tester) async {
      final working =
          await tester.runAsync(() => prepareAvatarImage(_png(30, 20)));

      expect(working!.width, 30);
    });
  });

  group('ritaglio', () {
    test('un JPEG di 512×512', () {
      final working = prepareAvatarImageSync(_png(400, 200));

      final jpeg = cropAvatarImageSync(working.bytes, const CropArea(100, 0, 200));

      final out = img.decodeJpg(jpeg)!;
      expect((out.width, out.height), (avatarOutputSize, avatarOutputSize));
    });

    test('un riquadro che esce dall\'immagine si stringe dentro', () {
      final working = prepareAvatarImageSync(_png(400, 200));

      final jpeg =
          cropAvatarImageSync(working.bytes, const CropArea(350, -10, 300));

      expect(img.decodeJpg(jpeg)!.width, avatarOutputSize);
    });
  });
}
