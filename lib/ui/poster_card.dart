import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import '../core/jellyfin/item_models.dart';
import '../features/library/library_providers.dart';
import '../features/library/user_data.dart';
import 'card_play_button.dart';
import 'wf_image.dart';

/// Locandina 2:3 con titolo, anno, avanzamento e badge "visto".
/// Con [width] `null` occupa la larghezza disponibile (griglie).
class PosterCard extends ConsumerStatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onPlay,
    this.width,
  });

  final JellyfinItem item;
  final VoidCallback onTap;

  /// Se presente, al passaggio del mouse compare il pulsante play.
  final VoidCallback? onPlay;
  final double? width;

  @override
  ConsumerState<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<PosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final userData = watchUserData(ref, item);
    final progress = userData.progress;
    final unplayed = userData.unplayedItemCount ?? 0;
    final year = item.productionYear;

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
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
                        WfImage(image: ref.watch(imageUrlsProvider).poster(item)),
                        if (progress != null) ProgressStrip(progress: progress),
                        if (userData.played)
                          const Positioned(
                              top: 6, right: 6, child: WatchedBadge())
                        else if (item.kind == ItemKind.series && unplayed > 0)
                          Positioned(
                              top: 6, right: 6, child: CountBadge(count: unplayed)),
                        if (_hover && widget.onPlay != null)
                          Center(
                              child: CardPlayButton(onPressed: widget.onPlay!)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (year != null)
                Text('$year',
                    style:
                        const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra oro in fondo all'immagine, per il minutaggio.
class ProgressStrip extends StatelessWidget {
  const ProgressStrip({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        height: 3,
        color: Colors.black54,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress,
          child: const ColoredBox(color: WfColors.gold),
        ),
      ),
    );
  }
}

class WatchedBadge extends StatelessWidget {
  const WatchedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration:
          const BoxDecoration(color: WfColors.gold, shape: BoxShape.circle),
      child: const Icon(LucideIcons.check, size: 14, color: WfColors.bg),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: WfColors.gold, borderRadius: BorderRadius.circular(10)),
      child: Text('$count',
          style: const TextStyle(
              color: WfColors.bg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
