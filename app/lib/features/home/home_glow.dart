import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../core/jellyfin/item_models.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';

/// Altezza dell'alone e tratto in cui sfuma dall'alto (spec §5.4).
const homeGlowHeight = 640.0;
const homeGlowFadeIn = 140.0;

/// L'alone sotto il carosello: il fondale del titolo mostrato, sfocato, che
/// sfuma dall'alto e verso il basso. Lo sfocato non è un filtro (pesa su
/// telefono, web e Fire Stick): è il fondale largo 32 px, ingrandito.
class HomeGlow extends ConsumerWidget {
  const HomeGlow({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(imageUrlsProvider).backdrop(item, maxWidth: 32);
    return SizedBox(
      height: homeGlowHeight,
      child: AnimatedSwitcher(
        duration: WfMotion.of(context).isReduced
            ? Duration.zero
            : WfMotion.crossfade,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey(item.id),
          child: image == null
              ? const SizedBox.shrink()
              : Opacity(
                  opacity: 0.28,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [
                        Colors.transparent,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0, homeGlowFadeIn / rect.height, 1],
                    ).createShader(rect),
                    child: WfImage(image: image, fallbackIcon: null),
                  ),
                ),
        ),
      ),
    );
  }
}
