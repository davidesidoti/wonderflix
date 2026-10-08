import 'dart:io' show ZLibCodec;
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
  // Niente EXIF nel PNG di lavoro, e quindi nemmeno nel JPEG caricato: le
  // immagini degli utenti sono pubbliche, e l'EXIF di una foto può dire dove
  // è stata scattata (GPS), quando e con cosa. Si toglie qui, senza contare
  // su `encodePng` (che oggi non lo scrive).
  image.exif = img.ExifData();
  return WorkingImage(img.encodePng(image), image.width, image.height);
}

/// Larghezza e altezza accettabili: positive, e non più di [maxSourcePixels]
/// in tutto. Lancia [AvatarImageException].
void _checkSize(int width, int height) {
  if (width <= 0 || height <= 0) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  if (width * height > maxSourcePixels) {
    throw const AvatarImageException(AvatarImageError.tooLarge);
  }
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
  _checkSize(size.width, size.height);
  return _decodeOrInvalid(() => img.decodeJpg(bytes));
}

/// Gli altri formati che si possono scegliere (PNG, GIF, WebP, BMP):
/// `startDecode` legge solo l'intestazione. Ogni altro formato che il
/// pacchetto `image` riconosce (ICO, TIFF, PSD, ...) non è valido: le sue
/// misure non sono controllate qui (un ICO può contenere un PNG enorme).
img.Image _decodeOther(Uint8List bytes) {
  final header = _readHeader(bytes);
  if (header == null) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  final (decoder, info) = header;
  final accepted = decoder is img.PngDecoder ||
      decoder is img.GifDecoder ||
      decoder is img.WebPDecoder ||
      decoder is img.BmpDecoder;
  if (!accepted) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  // Di un WebP animato `startDecode` dà la tela, ma il fotogramma ha le sue
  // misure, non controllate: non si accetta. (Di una GIF il fotogramma sta
  // sempre dentro la tela.)
  if (info is img.WebPInfo &&
      (info.hasAnimation || info.format == img.WebPFormat.animated)) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  _checkSize(info.width, info.height);
  if (info is img.PngInfo && !_pngInflatesWithin(bytes, _pngDataLimit(info))) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  // Di una GIF animata vale il primo fotogramma: si decodifica solo quello
  // (con tutti, `encodePng` scriverebbe un PNG animato).
  return _decodeOrInvalid(() => decoder.decodeFrame(0));
}

/// Byte in più che un PNG può espandere oltre le sue righe, per un encoder
/// poco preciso.
const _pngInflateSlack = 1024;

/// I passaggi dell'interlacciamento Adam7: colonna e riga di partenza, passo
/// orizzontale e verticale.
const _adam7Passes = [
  (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), //
  (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
];

/// I byte che i dati di un PNG (IDAT) danno al massimo, decompressi: ogni
/// riga ha il byte del filtro e i suoi pixel; interlacciato, le righe di ogni
/// passaggio.
int _pngDataLimit(img.PngInfo info) {
  final channels = switch (info.colorType) {
    2 => 3, // RGB
    4 => 2, // grigi con alfa
    6 => 4, // RGBA
    _ => 1, // grigi, tavolozza
  };
  int rows(int width, int height) => width <= 0 || height <= 0
      ? 0
      : height * (1 + (width * channels * info.bits + 7) ~/ 8);
  final width = info.width;
  final height = info.height;
  if (info.interlaceMethod == 0) return rows(width, height) + _pngInflateSlack;
  var total = 0;
  for (final (x, y, dx, dy) in _adam7Passes) {
    total += rows((width - x + dx - 1) ~/ dx, (height - y + dy - 1) ~/ dy);
  }
  return total + _pngInflateSlack;
}

/// I dati IDAT di [bytes] (un PNG già riconosciuto) si espandono al massimo
/// di [limit] byte. Si decomprimono a pezzi contando i byte, senza tenerli:
/// il decoder del pacchetto `image` li espande tutti in memoria, anche
/// gigabyte da un file di pochi MB.
bool _pngInflatesWithin(Uint8List bytes, int limit) {
  final counter = _CountingSink(limit);
  final inflater = ZLibCodec().decoder.startChunkedConversion(counter);
  try {
    // Dopo la firma (8 byte), i blocchi: lunghezza (4), tipo (4), dati e CRC
    // (4).
    var i = 8;
    while (i + 8 <= bytes.length) {
      final length = ByteData.sublistView(bytes, i, i + 4).getUint32(0);
      final type = String.fromCharCodes(bytes, i + 4, i + 8);
      final end = i + 8 + length;
      if (end + 4 > bytes.length) return false;
      if (type == 'IDAT') inflater.add(Uint8List.sublistView(bytes, i + 8, end));
      if (type == 'IEND') break;
      i = end + 4;
    }
    inflater.close();
    return true;
  } on Object {
    return false;
  }
}

/// Conta i byte decompressi, e si ferma oltre [limit].
class _CountingSink implements Sink<List<int>> {
  _CountingSink(this.limit);

  final int limit;
  int _count = 0;

  @override
  void add(List<int> data) {
    _count += data.length;
    if (_count > limit) throw const FormatException('PNG troppo grande');
  }

  @override
  void close() {}
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

/// Componenti al massimo di un JPEG (lo standard ne ammette 4 in un'immagine
/// a colori: CMYK).
const _maxJpegComponents = 4;

/// Fattore di campionamento massimo di una componente JPEG (standard: 1-4).
const _maxJpegSampling = 4;

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
      // (2), numero di componenti (1), poi 3 byte per componente.
      if (length < 8 || i + 8 > bytes.length) return null;
      // Il decoder alloca i blocchi di ogni componente, moltiplicati per il
      // campionamento: oltre i limiti dello standard, anche un'immagine
      // piccola occuperebbe gigabyte.
      final components = bytes[i + 7];
      if (components < 1 || components > _maxJpegComponents) return null;
      if (length < 8 + 3 * components ||
          i + 8 + 3 * components > bytes.length) {
        return null;
      }
      for (var c = 0; c < components; c++) {
        final sampling = bytes[i + 9 + 3 * c];
        final horizontal = sampling >> 4;
        final vertical = sampling & 0x0F;
        if (horizontal < 1 ||
            horizontal > _maxJpegSampling ||
            vertical < 1 ||
            vertical > _maxJpegSampling) {
          return null;
        }
      }
      return (
        width: (bytes[i + 5] << 8) | bytes[i + 6],
        height: (bytes[i + 3] << 8) | bytes[i + 4],
      );
    }
    i += length;
  }
  return null;
}

/// Il decoder del file e la sua intestazione, senza decodificare l'immagine.
/// `null` se non è un'immagine.
(img.Decoder, img.DecodeInfo)? _readHeader(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (decoder == null || info == null) return null;
    return (decoder, info);
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
