import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Le estensioni che si possono scegliere (spec K §10.3).
const avatarFileExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];

/// Un file più grande: "Immagine troppo grande" (spec K §10.3).
const maxAvatarFileBytes = 20 * 1024 * 1024;

/// Lato massimo dell'immagine di lavoro: basta per un avatar di 512 px anche
/// a 4×, e tiene leggero il ritaglio.
const maxWorkingSide = 2048;

/// Lato dell'immagine caricata (spec K §10.3).
const avatarOutputSize = 512;

/// Qualità del JPEG caricato.
const avatarJpegQuality = 90;

enum AvatarImageError { tooLarge, invalid }

class AvatarImageException implements Exception {
  const AvatarImageException(this.reason);

  final AvatarImageError reason;

  @override
  String toString() => 'AvatarImageException($reason)';
}

/// L'immagine da ritagliare: raddrizzata secondo l'EXIF, al massimo
/// [maxWorkingSide] per lato, in PNG.
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
  img.Image? decoded;
  try {
    // Di una GIF animata vale il primo fotogramma: si decodifica solo quello
    // (con tutti, `encodePng` scriverebbe un PNG animato).
    decoded = img.decodeImage(bytes, frame: 0);
  } on Object {
    decoded = null;
  }
  if (decoded == null) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  var image = img.bakeOrientation(decoded);
  if (math.max(image.width, image.height) > maxWorkingSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxWorkingSide)
        : img.copyResize(image, height: maxWorkingSide);
  }
  return WorkingImage(img.encodePng(image), image.width, image.height);
}

/// Ritaglia in un isolate [area] dall'immagine di lavoro: un JPEG di
/// [avatarOutputSize] di lato. Le parti trasparenti diventano nere.
Future<Uint8List> cropAvatarImage(Uint8List workingPng, CropArea area) =>
    Isolate.run(() => cropAvatarImageSync(workingPng, area));

/// Come [cropAvatarImage], nel thread di chi chiama. Un riquadro che esce
/// dall'immagine si stringe dentro.
Uint8List cropAvatarImageSync(Uint8List workingPng, CropArea area) {
  final image = img.decodePng(workingPng)!;
  final x = area.left.round().clamp(0, image.width - 1);
  final y = area.top.round().clamp(0, image.height - 1);
  final maxSide = math.min(image.width - x, image.height - y);
  final side = area.side.round().clamp(1, maxSide);
  final square = img.copyCrop(image, x: x, y: y, width: side, height: side);
  final resized = img.copyResize(
    square,
    width: avatarOutputSize,
    height: avatarOutputSize,
    interpolation: side > avatarOutputSize
        ? img.Interpolation.average
        : img.Interpolation.linear,
  );
  return img.encodeJpg(resized, quality: avatarJpegQuality);
}
