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

/// La posizione del marcatore SOF0 (`FF C0`) di un JPEG fatto da `encodeJpg`.
int _sof0(Uint8List bytes) {
  for (var i = 0; i < bytes.length - 1; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xC0) return i;
  }
  throw StateError('nessun SOF0');
}

/// Un JPEG vero di 16×16; con [declare] il suo SOF0 dichiara un'altra
/// larghezza e altezza.
Uint8List _jpeg({(int, int)? declare}) {
  final bytes = img.encodeJpg(img.Image(width: 16, height: 16));
  if (declare != null) {
    final sof = _sof0(bytes);
    ByteData.sublistView(bytes)
      ..setUint16(sof + 5, declare.$2)
      ..setUint16(sof + 7, declare.$1);
  }
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

    test('un JPEG che dichiara troppi pixel: troppo grande, subito', () {
      final stopwatch = Stopwatch()..start();

      // 65535×65535: decodificarlo, o anche solo prepararlo, vorrebbe dire
      // allocare decine di GB.
      expect(() => prepareAvatarImageSync(_jpeg(declare: (65535, 65535))),
          _fails(AvatarImageError.tooLarge));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('un JPEG con l\'intestazione troncata: non valida', () {
      final bytes = _jpeg();

      expect(() => prepareAvatarImageSync(bytes.sublist(0, _sof0(bytes) + 4)),
          _fails(AvatarImageError.invalid));
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

  group('dimensioni di un JPEG dall\'intestazione', () {
    test('larghezza e altezza del SOF', () {
      expect(readJpegSize(_jpeg()), (width: 16, height: 16));
      expect(readJpegSize(_jpeg(declare: (3000, 2000))),
          (width: 3000, height: 2000));
    });

    test('byte di riempimento e marcatori senza lunghezza prima del SOF', () {
      final bytes = _jpeg();
      // Dopo SOI: un riempimento (FF) e un RST0 (FF D0), poi il resto.
      final padded = Uint8List.fromList(
          [0xFF, 0xD8, 0xFF, 0xFF, 0xD0, ...bytes.sublist(2)]);

      expect(readJpegSize(padded), (width: 16, height: 16));
    });

    test('un JPEG progressivo (SOF2), e i segmenti che il decoder salta per '
        'lunghezza (COM, DRI)', () {
      final bytes = _jpeg();
      final progressive = Uint8List.fromList(bytes)..[_sof0(bytes) + 1] = 0xC2;
      expect(readJpegSize(progressive), (width: 16, height: 16));

      final withSegments = Uint8List.fromList([
        0xFF, 0xD8, //
        0xFF, 0xFE, 0x00, 0x05, 0x61, 0x62, 0x63, // COM "abc"
        0xFF, 0xDD, 0x00, 0x04, 0x00, 0x00, // DRI
        ...bytes.sublist(2),
      ]);
      expect(readJpegSize(withSegments), (width: 16, height: 16));
      // Il decoder fa la stessa strada: il file si decodifica.
      expect(prepareAvatarImageSync(withSegments).width, 16);
    });

    test('un SOF nascosto dietro FF 00: nessuna dimensione, e subito "non '
        'valida"', () {
      // Un SOF0 che dichiara 12000×12000.
      const hidden = [
        0xFF, 0xC0, 0x00, 0x11, 0x08, 0x2E, 0xE0, 0x2E, 0xE0, //
        0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
      ];
      // Letto come lunghezza, "FF 00 00 LL" salterebbe il SOF nascosto e
      // arriverebbe al JPEG vero di 16×16; il decoder invece salta FF 00
      // cercando il prossimo FF, e trova il SOF nascosto.
      final crafted = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0x00, 0x00, 2 + hidden.length, //
        ...hidden,
        ..._jpeg().sublist(2),
      ]);

      expect(readJpegSize(crafted), isNull);
      final stopwatch = Stopwatch()..start();
      expect(() => prepareAvatarImageSync(crafted),
          _fails(AvatarImageError.invalid));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('un marcatore che il decoder non legge per lunghezza, anche con una '
        'lunghezza giusta: nessuna dimensione', () {
      final rest = _jpeg().sublist(2);
      for (final marker in [
        0x00, 0xD8, 0xC8, 0xCC, 0xDC, 0xDE, 0xDF, 0xF0, 0xFD, //
      ]) {
        final crafted = Uint8List.fromList(
            [0xFF, 0xD8, 0xFF, marker, 0x00, 0x04, 0xAA, 0xBB, ...rest]);
        expect(readJpegSize(crafted), isNull,
            reason: 'marcatore ${marker.toRadixString(16)}');
      }
    });

    test('troncata o rovinata: nessuna dimensione', () {
      final bytes = _jpeg();
      final sof = _sof0(bytes);

      expect(readJpegSize(bytes.sublist(0, sof + 6)), isNull);
      expect(readJpegSize(bytes.sublist(0, sof)), isNull);
      expect(readJpegSize(Uint8List.fromList([0xFF, 0xD8, 0x00, 0x00])),
          isNull);
      expect(readJpegSize(Uint8List.fromList([0xFF, 0xD8])), isNull);
    });
  });

  group('ritaglio', () {
    test('l\'EXIF non arriva mai al JPEG caricato (anche il GPS)', () {
      final photo = img.Image(width: 300, height: 200);
      photo.exif.imageIfd.orientation = 6;
      photo.exif.imageIfd['Make'] = 'Fotocamera';
      photo.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
      photo.exif.gpsIfd[0x0002] = img.IfdValueRational(45, 1);
      final source = img.encodeJpg(photo);
      expect(img.decodeJpg(source)!.exif.gpsIfd.isEmpty, isFalse);

      final working = prepareAvatarImageSync(source);
      final jpeg = cropAvatarImageSync(working.bytes, const CropArea(0, 0, 200));

      expect(img.decodeJpg(jpeg)!.exif.isEmpty, isTrue);
    });

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
