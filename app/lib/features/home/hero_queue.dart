import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/jellyfin/item_models.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';

/// Le locandine dei prossimi tre titoli del carosello, nell'ordine in cui
/// arriveranno (spec §5.3). Sotto la prima una linea si riempie d'oro col
/// tempo della diapositiva ([progress]); un clic porta a quel titolo.
class HeroQueue extends ConsumerWidget {
  const HeroQueue({
    super.key,
    required this.items,
    required this.index,
    required this.progress,
    required this.onSelect,
  });

  final List<JellyfinItem> items;
  final int index;
  final Animation<double> progress;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = math.min(3, items.length - 1);
    if (count <= 0) return const SizedBox.shrink();
    final tv = FormFactor.of(context).tv;
    final urls = ref.watch(imageUrlsProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var k = 1; k <= count; k++) ...[
          if (k > 1) SizedBox(width: tv ? 10 : 12),
          _tile((index + k) % items.length, urls, tv: tv, next: k == 1),
        ],
      ],
    );
  }

  Widget _tile(int n, ImageUrls urls, {required bool tv, required bool next}) =>
      _QueueTile(
        key: ValueKey('hero-queue-$n'),
        item: items[n],
        poster: urls.poster(items[n]),
        width: next ? (tv ? 72 : 108) : (tv ? 62 : 92),
        progress: next ? progress : null,
        onTap: () => onSelect(n),
      );
}

class _QueueTile extends StatefulWidget {
  const _QueueTile({
    super.key,
    required this.item,
    required this.poster,
    required this.width,
    required this.progress,
    required this.onTap,
  });

  final JellyfinItem item;
  final ImageRef? poster;
  final double width;

  /// Solo la prima: il tempo della diapositiva.
  final Animation<double>? progress;
  final VoidCallback onTap;

  @override
  State<_QueueTile> createState() => _QueueTileState();
}

class _QueueTileState extends State<_QueueTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final progress = widget.progress;
    final next = progress != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          // Col mouse sopra si alza di 3 px.
          transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
          duration: motion.duration(WfMotion.fast),
          child: AnimatedOpacity(
            opacity: next || _hovered ? 1 : 0.75,
            duration: motion.duration(WfMotion.fast),
            child: SizedBox(
              width: widget.width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: WfImage(image: widget.poster),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: next ? WfColors.cream : WfColors.creamMuted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // Le altre tengono lo spazio della linea: le locandine
                  // restano allineate in basso.
                  SizedBox(
                    height: 2,
                    child: progress == null
                        ? null
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(1),
                            child: ColoredBox(
                              color: WfColors.cream.withValues(alpha: 0.2),
                              child: AnimatedBuilder(
                                animation: progress,
                                builder: (context, _) => FractionallySizedBox(
                                  key: const Key('hero-queue-fill'),
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.value,
                                  child: const ColoredBox(color: WfColors.gold),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nello stretto, al posto della coda: una tacca per titolo (spec §12). Le
/// passate oro, l'attuale si riempie col tempo, le future al 20%. Ognuna si
/// tocca su [minTouchTarget] di altezza.
class HeroTicks extends StatelessWidget {
  const HeroTicks({
    super.key,
    required this.count,
    required this.index,
    required this.progress,
    required this.onSelect,
  });

  final int count;
  final int index;
  final Animation<double> progress;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < count; i++)
        Expanded(
          child: GestureDetector(
            key: ValueKey('hero-tick-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: SizedBox(
              height: minTouchTarget,
              child: Center(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: i < index
                        ? WfColors.gold
                        : WfColors.cream.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(1),
                  ),
                  child: i == index
                      ? AnimatedBuilder(
                          animation: progress,
                          builder: (context, _) => FractionallySizedBox(
                            key: const Key('hero-tick-fill'),
                            alignment: Alignment.centerLeft,
                            widthFactor: progress.value,
                            child: const ColoredBox(color: WfColors.gold),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
