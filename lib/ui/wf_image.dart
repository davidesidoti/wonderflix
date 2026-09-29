import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import '../core/jellyfin/image_urls.dart';

typedef ImageBuilderFn = Widget Function(ImageRef image, BoxFit fit);

Widget _networkImage(ImageRef image, BoxFit fit) => CachedNetworkImage(
      imageUrl: image.url,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => ImagePlaceholder(blurHash: image.blurHash),
      errorWidget: (context, url, error) => const ImagePlaceholder(),
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

class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({super.key, this.blurHash, this.icon});

  final String? blurHash;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hash = blurHash;
    if (hash != null) return BlurHash(hash: hash);
    final symbol = icon;
    return ColoredBox(
      color: WfColors.surfaceHigh,
      child: symbol == null
          ? null
          : Center(child: Icon(symbol, color: WfColors.creamMuted, size: 28)),
    );
  }
}
