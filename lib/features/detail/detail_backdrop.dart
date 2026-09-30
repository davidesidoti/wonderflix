import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/hero_launch.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../ui/backdrop_image.dart';
import '../library/library_providers.dart';
import 'header_parallax.dart';

/// Sfondo della scheda, dietro al contenuto. Con lo scroll della pagina sale
/// a metà velocità, si ingrandisce e si scurisce (parallasse, spec C §9.1);
/// con le animazioni ridotte segue lo scroll e basta. È ritagliato alla
/// parte della testata ancora sullo schermo. Mentre la scheda carica usa le
/// immagini di [launch]: è la destinazione del volo Hero, e deve esserci
/// dal primo fotogramma (spec C §6.2).
class DetailBackdrop extends ConsumerWidget {
  const DetailBackdrop({
    super.key,
    required this.item,
    required this.launch,
    required this.controller,
  });

  /// `null` mentre la scheda carica.
  final JellyfinItem? item;
  final HeroLaunch? launch;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    final current = item;
    // Stesso URL della card (`openItem` usa `urls.backdrop`): all'arrivo dei
    // dati l'immagine non cambia.
    final image = BackdropImage(
      backdrop: current != null ? urls.backdrop(current) : launch?.image,
      fallback: current != null ? urls.poster(current) : launch?.fallback,
    );
    final reduced = WfMotion.of(context).isReduced;
    return AnimatedBuilder(
      animation: controller,
      child: WfHero(
          tag: launch?.tag, borderRadius: BorderRadius.zero, child: image),
      builder: (context, child) {
        final p = headerParallax(
            controller.hasClients ? controller.offset : 0, reduced: reduced);
        return ClipRect(
          clipper: _VisibleHeader(p.visibleHeight),
          child: Transform.translate(
            offset: Offset(0, p.backdropShift),
            child: Transform.scale(
              scale: p.backdropScale,
              alignment: Alignment.topCenter,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child!,
                  if (p.dim > 0)
                    ColoredBox(color: WfColors.bg.withValues(alpha: p.dim)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ritaglia lo sfondo alla parte della testata ancora sullo schermo.
class _VisibleHeader extends CustomClipper<Rect> {
  const _VisibleHeader(this.height);

  final double height;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, height.clamp(0.0, size.height));

  @override
  bool shouldReclip(_VisibleHeader oldClipper) => oldClipper.height != height;
}
