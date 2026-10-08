import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Lato delle immagini della galleria, in pixel (spec K §10.2).
const galleryAvatarSize = 512;

/// L'icona occupa questa parte del lato.
const _iconScale = 0.55;

/// Colore dell'icona.
const _iconColor = Color(0xFFFFFFFF);

/// Le 8 sfumature, dai colori di WonderFlix: dall'alto a sinistra al basso a
/// destra.
const galleryGradients = <(Color, Color)>[
  (Color(0xFFD4A64A), Color(0xFF7A5A1E)), // oro
  (Color(0xFFC8463C), Color(0xFF5E1C17)), // rosso sipario
  (Color(0xFF2E8B85), Color(0xFF123B38)), // verde acqua
  (Color(0xFF4F5BD5), Color(0xFF1F2560)), // blu notte
  (Color(0xFF8E4FC8), Color(0xFF3D1C5A)), // viola
  (Color(0xFF5BBF6A), Color(0xFF24502B)), // verde
  (Color(0xFFE07A2E), Color(0xFF6E3410)), // arancio
  (Color(0xFF5A6472), Color(0xFF22262D)), // ardesia
];

/// Le icone, a tema cinema e serate. Lucide 3.1.20 non ha il gufo: c'è
/// l'uccello.
const _icons = <IconData>[
  LucideIcons.popcorn,
  LucideIcons.clapperboard,
  LucideIcons.film,
  LucideIcons.ticket,
  LucideIcons.tv,
  LucideIcons.projector,
  LucideIcons.video,
  LucideIcons.star,
  LucideIcons.rocket,
  LucideIcons.ghost,
  LucideIcons.cat,
  LucideIcons.dog,
  LucideIcons.rabbit,
  LucideIcons.bird,
  LucideIcons.fish,
  LucideIcons.skull,
  LucideIcons.crown,
  LucideIcons.heart,
  LucideIcons.music,
  LucideIcons.gamepad2,
  LucideIcons.pizza,
  LucideIcons.coffee,
  LucideIcons.sparkles,
  LucideIcons.moon,
];

/// Un avatar della galleria: un'icona bianca su una sfumatura.
class GalleryAvatar {
  const GalleryAvatar(this.icon, this.colors);

  final IconData icon;
  final (Color, Color) colors;
}

/// I 24 avatar (spec K §10.2): le sfumature si ripetono in ordine, quindi due
/// icone vicine hanno colori diversi.
final galleryAvatars = List<GalleryAvatar>.unmodifiable([
  for (var i = 0; i < _icons.length; i++)
    GalleryAvatar(_icons[i], galleryGradients[i % galleryGradients.length]),
]);

/// Disegna [avatar] in un quadrato di lato [size].
void paintGalleryAvatar(Canvas canvas, double size, GalleryAvatar avatar) {
  final rect = Offset.zero & Size.square(size);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
          rect.topLeft, rect.bottomRight, [avatar.colors.$1, avatar.colors.$2]),
  );
  final icon = avatar.icon;
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size * _iconScale,
        height: 1,
        color: _iconColor,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2));
  painter.dispose();
}

/// [avatar] come PNG di [galleryAvatarSize]×[galleryAvatarSize] (spec K §10.2):
/// l'immagine che si carica.
Future<Uint8List> renderGalleryAvatar(GalleryAvatar avatar) async {
  final recorder = ui.PictureRecorder();
  paintGalleryAvatar(Canvas(recorder), galleryAvatarSize.toDouble(), avatar);
  final picture = recorder.endRecording();
  final image = await picture.toImage(galleryAvatarSize, galleryAvatarSize);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// L'anteprima di un avatar della galleria: lo stesso disegno, in piccolo e
/// rotondo.
class GalleryAvatarView extends StatelessWidget {
  const GalleryAvatarView({super.key, required this.avatar, required this.size});

  final GalleryAvatar avatar;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: CustomPaint(
            size: Size.square(size), painter: _GalleryAvatarPainter(avatar)),
      );
}

class _GalleryAvatarPainter extends CustomPainter {
  _GalleryAvatarPainter(this.avatar);

  final GalleryAvatar avatar;

  @override
  void paint(Canvas canvas, Size size) =>
      paintGalleryAvatar(canvas, size.shortestSide, avatar);

  @override
  bool shouldRepaint(_GalleryAvatarPainter oldDelegate) =>
      oldDelegate.avatar != avatar;
}
