import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Le estensioni che si possono scegliere (spec K §10.3).
const avatarFileExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];

/// Un file più grande: "Immagine troppo grande" (spec K §10.3).
const maxAvatarFileBytes = 20 * 1024 * 1024;

/// Pixel al massimo dell'immagine scelta, letti dall'intestazione prima di
/// decodificare: oltre, "Immagine troppo grande". Un file piccolo può
/// dichiarare un'immagine enorme, che in memoria non starebbe.
const maxSourcePixels = 64 * 1000 * 1000;

/// Lato massimo dell'immagine di lavoro: basta per un avatar di 512 px anche
/// a 4×, e tiene leggero il ritaglio.
const maxWorkingSide = 2048;

/// Lato dell'immagine caricata (spec K §10.3).
const avatarOutputSize = 512;

/// Qualità del JPEG caricato.
const avatarJpegQuality = 90;

/// Il colore delle parti trasparenti, come `WfColors.surfaceHigh` (qui niente
/// Flutter: il lavoro è in un isolate). Il JPEG non ha trasparenza: il
/// colore va già nell'immagine di lavoro, così l'anteprima del ritaglio è
/// uguale all'immagine caricata.
const transparentFill = 0xFF1B1B1B;

enum AvatarImageError { tooLarge, invalid }

class AvatarImageException implements Exception {
  const AvatarImageException(this.reason);

  final AvatarImageError reason;

  @override
  String toString() => 'AvatarImageException($reason)';
}

/// L'immagine da ritagliare: raddrizzata secondo l'EXIF, al massimo
/// [maxWorkingSide] per lato, a 8 bit per canale e senza trasparenza, in PNG.
class WorkingImage {
  const WorkingImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// La parte da tenere, in pixel dell'immagine di lavoro: un quadrato.
class CropArea {
  const CropArea(this.left, this.top, this.side);

  final double left;
  final double top;
  final double side;

  @override
  bool operator ==(Object other) =>
      other is CropArea &&
      other.left == left &&
      other.top == top &&
      other.side == side;

  @override
  int get hashCode => Object.hash(left, top, side);

  @override
  String toString() => 'CropArea($left, $top, $side)';
}

/// Prepara in un isolate il file scelto (spec K §10.3). Lancia
/// [AvatarImageException].
Future<WorkingImage> prepareAvatarImage(Uint8List bytes) =>
    Isolate.run(() => prepareAvatarImageSync(bytes));

/// Come [prepareAvatarImage], nel thread di chi chiama.
WorkingImage prepareAvatarImageSync(Uint8List bytes) {
  if (bytes.length > maxAvatarFileBytes) {
    throw const AvatarImageException(AvatarImageError.tooLarge);
  }
  final header = _readHeader(bytes);
  if (header == null) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  final (decoder, pixels) = header;
  if (pixels > maxSourcePixels) {
    throw const AvatarImageException(AvatarImageError.tooLarge);
  }
  img.Image? decoded;
  try {
    // Di una GIF animata vale il primo fotogramma: si decodifica solo quello
    // (con tutti, `encodePng` scriverebbe un PNG animato).
    decoded = decoder.decodeFrame(0);
  } on Object {
    decoded = null;
  }
  if (decoded == null) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  final image = _toWorking(decoded);
  return WorkingImage(img.encodePng(image), image.width, image.height);
}

/// Il decoder del file e i pixel che dichiara la sua intestazione, senza
/// decodificare l'immagine. `null` se non è un'immagine.
(img.Decoder, int)? _readHeader(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (decoder == null || info == null) return null;
    return (decoder, info.width * info.height);
  } on Object {
    return null;
  }
}

/// L'immagine di lavoro: ridotta, a 8 bit per canale, senza trasparenza e
/// raddrizzata. Il lavoro a piena risoluzione è solo la riduzione.
img.Image _toWorking(img.Image decoded) {
  var image = decoded;
  // Gli indici di una tavolozza non si possono mediare riducendo: prima i
  // colori veri.
  if (image.hasPalette) {
    image = image.convert(format: img.Format.uint8, noAnimation: true);
  }
  // L'orientamento si applica alla fine, all'immagine piccola: `copyResize`
  // lo applicherebbe prima, a piena risoluzione.
  final orientation = image.exif.imageIfd.orientation ?? 1;
  image.exif.imageIfd.orientation = null;
  if (math.max(image.width, image.height) > maxWorkingSide) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: maxWorkingSide, interpolation: img.Interpolation.average)
        : img.copyResize(image,
            height: maxWorkingSide, interpolation: img.Interpolation.average);
  }
  // 16 bit, grigi a pochi bit, HDR: 8 bit per canale, come il JPEG.
  if (image.format != img.Format.uint8) {
    image = image.convert(format: img.Format.uint8, noAnimation: true);
  }
  if (image.hasAlpha) image = _flatten(image);
  if (orientation != 1) {
    image.exif.imageIfd.orientation = orientation;
    image = img.bakeOrientation(image);
  }
  return image;
}

/// [image] (8 bit per canale) senza trasparenza: sopra [transparentFill].
img.Image _flatten(img.Image image) {
  const fillR = (transparentFill >> 16) & 0xFF;
  const fillG = (transparentFill >> 8) & 0xFF;
  const fillB = transparentFill & 0xFF;
  final flat = img.Image(width: image.width, height: image.height);
  for (final pixel in image) {
    final alpha = pixel.aNormalized;
    flat.setPixelRgb(
      pixel.x,
      pixel.y,
      (pixel.r * alpha + fillR * (1 - alpha)).round(),
      (pixel.g * alpha + fillG * (1 - alpha)).round(),
      (pixel.b * alpha + fillB * (1 - alpha)).round(),
    );
  }
  return flat;
}

/// Ritaglia in un isolate [area] dall'immagine di lavoro: un JPEG di
/// [avatarOutputSize] di lato. La trasparenza l'ha già tolta la preparazione.
Future<Uint8List> cropAvatarImage(Uint8List workingPng, CropArea area) =>
    Isolate.run(() => cropAvatarImageSync(workingPng, area));

/// Come [cropAvatarImage], nel thread di chi chiama. Un riquadro più grande
/// dell'immagine si stringe al lato corto; uno che esce dall'immagine si
/// sposta dentro, senza rimpicciolire.
Uint8List cropAvatarImageSync(Uint8List workingPng, CropArea area) {
  final image = img.decodePng(workingPng)!;
  final shortSide = math.min(image.width, image.height);
  final side = area.side.round().clamp(1, shortSide);
  final x = area.left.round().clamp(0, image.width - side);
  final y = area.top.round().clamp(0, image.height - side);
  final square = img.copyCrop(image, x: x, y: y, width: side, height: side);
  final resized = img.copyResize(
    square,
    width: avatarOutputSize,
    height: avatarOutputSize,
    // Riducendo la media dei pixel; ingrandendo la bicubica, più morbida.
    interpolation: side > avatarOutputSize
        ? img.Interpolation.average
        : img.Interpolation.cubic,
  );
  return img.encodeJpg(resized, quality: avatarJpegQuality);
}
