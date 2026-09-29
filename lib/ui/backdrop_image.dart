import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/jellyfin/image_urls.dart';
import 'wf_image.dart';

/// Sfondo a tutta larghezza. Se il titolo non ha un'immagine di sfondo
/// (metadati incompleti sul server) usa la locandina, sfocata e scurita.
class BackdropImage extends StatelessWidget {
  const BackdropImage({super.key, required this.backdrop, required this.fallback});

  final ImageRef? backdrop;

  /// Di solito la locandina (`ImageUrls.poster`).
  final ImageRef? fallback;

  @override
  Widget build(BuildContext context) {
    final image = backdrop;
    if (image != null) return WfImage(image: image);
    final poster = fallback;
    if (poster == null) return const ColoredBox(color: WfColors.bg);
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.clamp),
          child: WfImage(image: poster, fallbackIcon: null),
        ),
        const ColoredBox(color: Color(0x730A0A0A)),
      ],
    );
  }
}
