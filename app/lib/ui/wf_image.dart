import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/motion.dart';
import '../app/theme.dart';
import '../core/jellyfin/image_urls.dart';

typedef ImageBuilderFn = Widget Function(ImageRef image, BoxFit fit);

/// Cache su disco dedicata alle immagini della libreria: più capiente e con
/// scadenza più lunga di quella predefinita.
final wonderflixImageCache = CacheManager(Config(
  'wonderflixImages',
  stalePeriod: const Duration(days: 30),
  maxNrOfCacheObjects: 5000,
));

Widget _networkImage(ImageRef image, BoxFit fit) => LayoutBuilder(
      builder: (context, constraints) {
        // Decodifica alla dimensione mostrata, non a quella originale.
        final width = constraints.maxWidth;
        final memWidth = width.isFinite && width > 0
            ? (width * MediaQuery.devicePixelRatioOf(context)).round()
            : null;
        if (kIsWeb) return webNetworkImage(image, fit, memWidth);
        return CachedNetworkImage(
          imageUrl: image.url,
          cacheManager: wonderflixImageCache,
          memCacheWidth: memWidth,
          fit: fit,
          fadeInDuration: WfMotion.fast,
          placeholder: (context, url) => ImagePlaceholder(blurHash: image.blurHash),
          errorWidget: (context, url, error) {
            // Sul web il pacchetto lascia l'errore nella cache di Flutter:
            // senza evict l'immagine resta vuota a ogni ritorno sulla pagina.
            scheduleMicrotask(() => ResizeImage.resizeIfNeeded(memWidth, null,
                    CachedNetworkImageProvider(url,
                        cacheManager: wonderflixImageCache))
                .evict());
            return const ImagePlaceholder(icon: LucideIcons.imageOff);
          },
        );
      },
    );

// CanvasKit su iPhone: la via <img> del pacchetto non crea le texture con tante immagini; NetworkImage decodifica i byte alla misura.
@visibleForTesting
Widget webNetworkImage(ImageRef image, BoxFit fit, int? memWidth) => Image(
      image: ResizeImage.resizeIfNeeded(
          memWidth, null, NetworkImage(image.url)),
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          wasSynchronouslyLoaded
              ? child
              : frame == null
                  ? ImagePlaceholder(blurHash: image.blurHash)
                  : TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: WfMotion.fast,
                      builder: (_, o, child) =>
                          Opacity(opacity: o, child: child),
                      child: child,
                    ),
      errorBuilder: (context, error, stackTrace) =>
          const ImagePlaceholder(icon: LucideIcons.imageOff),
    );

/// Come si disegna un'immagine di rete (sostituito nei widget test).
final imageBuilderProvider = Provider<ImageBuilderFn>((ref) => _networkImage);

/// Immagine Jellyfin con cache su disco e blurhash durante il caricamento.
class WfImage extends ConsumerWidget {
  const WfImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.fallbackIcon = LucideIcons.film,
  });

  final ImageRef? image;
  final BoxFit fit;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = image;
    if (img == null) return ImagePlaceholder(icon: fallbackIcon);
    return ref.watch(imageBuilderProvider)(img, fit);
  }
}

/// Sotto questo widget i segnaposto delle immagini sono trasparenti. Nel volo
/// Hero l'immagine della pagina sta sopra quella della card: finché lo
/// sfondo non è scaricato deve lasciar vedere la card, non un segnaposto.
class TransparentPlaceholders extends InheritedWidget {
  const TransparentPlaceholders({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TransparentPlaceholders>() !=
      null;

  @override
  bool updateShouldNotify(TransparentPlaceholders oldWidget) => false;
}

class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({super.key, this.blurHash, this.icon});

  final String? blurHash;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (TransparentPlaceholders.of(context)) return const SizedBox.expand();
    final hash = blurHash;
    // Senza `color` il pacchetto mostra un azzurro (`Colors.blueGrey`)
    // finché l'anteprima sfocata non è decodificata.
    if (hash != null) return BlurHash(hash: hash, color: WfColors.surfaceHigh);
    final symbol = icon;
    return ColoredBox(
      color: WfColors.surfaceHigh,
      child: symbol == null
          ? null
          : Center(child: Icon(symbol, color: WfColors.creamMuted, size: 28)),
    );
  }
}
