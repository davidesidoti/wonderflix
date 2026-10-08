import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/profiles/avatar_image.dart';

Uint8List _png(int width, int height) =>
    img.encodePng(img.Image(width: width, height: height));

Matcher _fails(AvatarImageError reason) => throwsA(
    isA<AvatarImageException>().having((e) => e.reason, 'reason', reason));

/// Il CRC-32 di un blocco PNG (tipo e dati).
int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// Un PNG di un pixel la cui intestazione dichiara [width]×[height].
Uint8List _pngDeclaring(int width, int height) {
  final bytes = _png(1, 1);
  final data = ByteData.sublistView(bytes);
  // Dopo la firma (8 byte), la lunghezza (4) e il tipo (4) del blocco IHDR
  // vengono larghezza e altezza; il CRC copre tipo e dati (13 byte).
  data.setUint32(16, width);
  data.setUint32(20, height);
  data.setUint32(29, _crc32(bytes.sublist(12, 29)));
  return bytes;
}

/// I canali rossi, verdi e blu di un pixel, a meno delle perdite del JPEG.
Matcher _rgb(int r, int g, int b) =>
    equals([closeTo(r, 40), closeTo(g, 40), closeTo(b, 40)]);

List<num> _channels(img.Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  return [pixel.r, pixel.g, pixel.b];
}

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

    test('una foto grande e girata: ridotta, poi raddrizzata', () {
      final photo = img.Image(width: 3000, height: 1000);
      photo.exif.imageIfd.orientation = 6;

      final working = prepareAvatarImageSync(img.encodeJpg(photo));

      expect((working.width, working.height), (683, maxWorkingSide));
    });

    test('un file che non è un\'immagine: non valida', () {
      expect(() => prepareAvatarImageSync(Uint8List.fromList([1, 2, 3, 4])),
          _fails(AvatarImageError.invalid));
    });

    test('oltre 20 MB: troppo grande, senza decodificare', () {
      expect(() => prepareAvatarImageSync(Uint8List(maxAvatarFileBytes + 1)),
          _fails(AvatarImageError.tooLarge));
    });

    test('troppi pixel nell\'intestazione: troppo grande, senza decodificare',
        () {
      // Lo stesso file con l'intestazione vera si decodifica.
      expect(prepareAvatarImageSync(_pngDeclaring(1, 1)).width, 1);

      // 10000×10000: i dati sono di un pixel, quindi decodificarlo darebbe
      // "non valida".
      expect(() => prepareAvatarImageSync(_pngDeclaring(10000, 10000)),
          _fails(AvatarImageError.tooLarge));
    });

    test('le parti trasparenti prendono il colore di fondo dell\'app: '
        'l\'anteprima è uguale al risultato', () {
      final image = img.Image(width: 2, height: 1, numChannels: 4)
        // Bianco, ma del tutto trasparente.
        ..setPixelRgba(0, 0, 255, 255, 255, 0)
        ..setPixelRgba(1, 0, 200, 0, 0, 255);

      final working = prepareAvatarImageSync(img.encodePng(image));

      final out = img.decodePng(working.bytes)!;
      expect(out.hasAlpha, isFalse);
      expect(transparentFill, WfColors.surfaceHigh.toARGB32());
      expect(_channels(out, 0, 0), [0x1B, 0x1B, 0x1B]);
      expect(_channels(out, 1, 0), [200, 0, 0]);
    });

    test('16 bit per canale e tavolozza: a 8 bit, senza tavolozza', () {
      final deep = img.Image(width: 2, height: 2, format: img.Format.uint16);
      for (final pixel in deep) {
        pixel.setRgb(65535, 0, 0);
      }
      final indexed = (img.Image(width: 2, height: 2)
            ..clear(img.ColorRgb8(0, 0, 200)))
          .convert(withPalette: true);
      expect(indexed.hasPalette, isTrue);

      for (final source in [deep, indexed]) {
        final out =
            img.decodePng(prepareAvatarImageSync(img.encodePng(source)).bytes)!;
        expect(out.format, img.Format.uint8);
        expect(out.hasPalette, isFalse);
      }
      final red = img.decodePng(prepareAvatarImageSync(img.encodePng(deep)).bytes)!;
      expect(_channels(red, 0, 0), [255, 0, 0]);
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

    test('un riquadro che esce dall\'immagine si sposta dentro, senza '
        'rimpicciolire', () {
      // 400×200: blu a sinistra, poi verde (200-299) e rosso (300-399).
      final image = img.Image(width: 400, height: 200)
        ..clear(img.ColorRgb8(0, 0, 255));
      for (final pixel in image) {
        if (pixel.x >= 300) {
          pixel.setRgb(255, 0, 0);
        } else if (pixel.x >= 200) {
          pixel.setRgb(0, 255, 0);
        }
      }
      final working = prepareAvatarImageSync(img.encodePng(image));

      final out = img.decodeJpg(
          cropAvatarImageSync(working.bytes, const CropArea(350, -10, 300)))!;

      expect((out.width, out.height), (avatarOutputSize, avatarOutputSize));
      // Il lato si stringe a 200 e il riquadro va sulla metà destra: verde a
      // sinistra, rosso a destra, niente blu.
      expect(_channels(out, 128, 256), _rgb(0, 255, 0));
      expect(_channels(out, 384, 256), _rgb(255, 0, 0));
      expect(_channels(out, 5, 5), _rgb(0, 255, 0));
    });
  });
}
