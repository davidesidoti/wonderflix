import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../core/jellyfin/item_models.dart';
import '../features/library/item_labels.dart';
import '../features/library/library_providers.dart';
import '../features/library/user_data.dart';
import 'card_play_button.dart';
import 'poster_card.dart';
import 'wf_image.dart';

/// Card 16:9 per "Continua a guardare", "Prossimi episodi" ed episodi.
class LandscapeCard extends ConsumerStatefulWidget {
  const LandscapeCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onPlay,
    this.width = 300,
  });

  final JellyfinItem item;
  final VoidCallback onTap;

  /// Se presente, al passaggio del mouse compare il pulsante play.
  final VoidCallback? onPlay;
  final double width;

  @override
  ConsumerState<LandscapeCard> createState() => _LandscapeCardState();
}

class _LandscapeCardState extends ConsumerState<LandscapeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final userData = watchUserData(ref, item);
    final progress = userData.progress;
    final subtitle = cardSubtitle(item);

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
                aspectRatio: 16 / 9,
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
                        WfImage(
                            image: ref.watch(imageUrlsProvider).landscape(item)),
                        if (progress != null) ProgressStrip(progress: progress),
                        if (userData.played)
                          const Positioned(top: 6, right: 6, child: WatchedBadge()),
                        if (_hover && widget.onPlay != null)
                          Center(
                              child: CardPlayButton(onPressed: widget.onPlay!)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(cardTitle(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (subtitle != null)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
