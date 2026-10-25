import 'package:flutter/material.dart';

import '../app/motion.dart';
import '../app/theme.dart';
import '../core/jellyfin/image_urls.dart';
import 'wf_image.dart';

/// Forma di una [RemoteImageCard], uguale alle card della libreria.
enum RemoteCardShape {
  /// Locandina 2:3, larga come le `PosterCard` della Home.
  poster(2 / 3, 160),

  /// Card 16:9, larga come le `LandscapeCard`.
  landscape(16 / 9, 300);

  const RemoteCardShape(this.aspectRatio, this.width);

  final double aspectRatio;
  final double width;
}

/// Card di un titolo con l'immagine da un indirizzo qualunque (TMDB, TVDB:
/// spec M §8.3), nello stile delle card della libreria: titolo, sottotitolo
/// ed etichetta in alto a sinistra, facoltativi. Senza [onTap] non si
/// clicca, e non cambia aspetto al passaggio del mouse.
class RemoteImageCard extends StatefulWidget {
  const RemoteImageCard({
    super.key,
    required this.shape,
    required this.image,
    required this.title,
    this.subtitle,
    this.badge,
    this.onTap,
    this.width,
  });

  final RemoteCardShape shape;
  final ImageRef? image;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final VoidCallback? onTap;

  /// Al posto della larghezza di [shape] (card più piccole nello stretto).
  final double? width;

  @override
  State<RemoteImageCard> createState() => _RemoteImageCardState();
}

class _RemoteImageCardState extends State<RemoteImageCard> {
  bool _hover = false;

  @override
  void didUpdateWidget(RemoteImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se il clic sparisce con il mouse sopra, il MouseRegion se ne va e
    // `onExit` non arriva mai: `_hover` resterebbe vero, e la card
    // tornerebbe cliccabile con il bordo oro anche a mouse lontano.
    if (widget.onTap == null) _hover = false;
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final subtitle = widget.subtitle;
    final badge = widget.badge;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: widget.shape.aspectRatio,
          child: AnimatedContainer(
            duration: WfMotion.fast,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _hover ? WfColors.gold : Colors.transparent,
                  width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WfImage(image: widget.image),
                  if (badge != null) Positioned(top: 6, left: 6, child: badge),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        if (subtitle != null)
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
      ],
    );
    return SizedBox(
      width: widget.width ?? widget.shape.width,
      child: onTap == null
          ? content
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(onTap: onTap, child: content),
            ),
    );
  }
}
