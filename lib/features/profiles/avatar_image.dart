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
  final image =
      _toWorking(_isJpeg(bytes) ? _decodeJpeg(bytes) : _decodeOther(bytes));
  // Il PNG di lavoro non ha l'EXIF (`encodePng` non lo scrive), e quindi
  // nemmeno il JPEG caricato: le immagini degli utenti sono pubbliche, e
  // l'EXIF di una foto può dire dove è stata scattata (GPS), quando e con
  // cosa.
  return WorkingImage(img.encodePng(image), image.width, image.height);
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

/// Un JPEG: le dimensioni dall'intestazione ([readJpegSize]), poi una sola
/// decodifica. Il decoder del pacchetto `image` alloca tutta l'immagine già
/// leggendo l'intestazione (`startDecode`), anche quella dichiarata da un
/// file rovinato.
img.Image _decodeJpeg(Uint8List bytes) {
  final size = readJpegSize(bytes);
  if (size == null) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  if (size.width * size.height > maxSourcePixels) {
    throw const AvatarImageException(AvatarImageError.tooLarge);
  }
  return _decodeOrInvalid(() => img.decodeJpg(bytes));
}

/// Gli altri formati (PNG, GIF, WebP, BMP): `startDecode` legge solo
/// l'intestazione.
img.Image _decodeOther(Uint8List bytes) {
  final header = _readHeader(bytes);
  if (header == null) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  final (decoder, pixels) = header;
  if (pixels > maxSourcePixels) {
    throw const AvatarImageException(AvatarImageError.tooLarge);
  }
  // Di una GIF animata vale il primo fotogramma: si decodifica solo quello
  // (con tutti, `encodePng` scriverebbe un PNG animato).
  return _decodeOrInvalid(() => decoder.decodeFrame(0));
}

img.Image _decodeOrInvalid(img.Image? Function() decode) {
  img.Image? decoded;
  try {
    decoded = decode();
  } on Object {
    decoded = null;
  }
  if (decoded == null) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  return decoded;
}

/// I marcatori SOF di un JPEG: da C0 a CF, tranne DHT (C4), JPG (C8) e DAC
/// (CC).
const _jpegSofMarkers = {
  0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, //
  0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
};

/// I segmenti che il decoder del pacchetto `image` salta per la loro
/// lunghezza, come [readJpegSize]: DHT, DQT, DRI, APP0-APP15 e COM.
bool _isJpegLengthSegment(int marker) =>
    marker == 0xC4 ||
    marker == 0xDB ||
    marker == 0xDD ||
    (marker >= 0xE0 && marker <= 0xEF) ||
    marker == 0xFE;

/// Larghezza e altezza di un JPEG lette dal primo SOF, senza decodificare:
/// si scorrono i segmenti dopo SOI con le loro lunghezze. `null` se
/// l'intestazione è troncata o rovinata.
///
/// Prima del SOF valgono solo i marcatori che il decoder legge allo stesso
/// modo (per lunghezza, o senza lunghezza). Gli altri il decoder li salta a
/// modo suo (FF 00 cercando il prossimo FF, un marcatore sconosciuto
/// tornando indietro di qualche byte): potrebbe trovare un SOF che qui non
/// si è visto, e allocare l'immagine che dichiara.
({int width, int height})? readJpegSize(Uint8List bytes) {
  if (!_isJpeg(bytes)) return null;
  var i = 2;
  while (i < bytes.length) {
    if (bytes[i] != 0xFF) return null;
    // I byte di riempimento (FF) prima del marcatore.
    while (i < bytes.length && bytes[i] == 0xFF) {
      i++;
    }
    if (i >= bytes.length) return null;
    final marker = bytes[i++];
    // Marcatori senza lunghezza: TEM e RST0-RST7.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
    // Tutto il resto (anche la fine dell'immagine, o i dati, prima del SOF):
    // rovinato.
    final isSof = _jpegSofMarkers.contains(marker);
    if (!isSof && !_isJpegLengthSegment(marker)) return null;
    if (i + 2 > bytes.length) return null;
    final length = (bytes[i] << 8) | bytes[i + 1];
    if (length < 2) return null;
    if (isSof) {
      // Dopo la lunghezza (2 byte): precisione (1), altezza (2), larghezza
      // (2) e numero di componenti (1).
      if (length < 8 || i + 7 > bytes.length) return null;
      return (
        width: (bytes[i + 5] << 8) | bytes[i + 6],
        height: (bytes[i + 3] << 8) | bytes[i + 4],
      );
    }
    i += length;
  }
  return null;
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
