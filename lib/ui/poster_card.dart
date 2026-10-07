import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/hero_launch.dart';
import '../app/motion.dart';
import '../app/navigation.dart';
import '../app/theme.dart';
import '../core/jellyfin/item_models.dart';
import '../features/library/library_providers.dart';
import '../features/library/user_data.dart';
import 'card_preview_host.dart';
import 'wf_image.dart';

/// Locandina 2:3 con titolo, anno, avanzamento e badge "visto".
/// Con [width] `null` occupa la larghezza disponibile (griglie). Con il
/// mouse fermo sopra si apre l'anteprima ([CardPreviewHost]).
class PosterCard extends ConsumerStatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    this.onTap,
    this.heroSource,
    this.width,
    this.markLabel,
  });

  final JellyfinItem item;
  final VoidCallback? onTap;

  /// Card da cui parte il volo Hero (per esempio `home.latestMovies.3`),
  /// dentro la pagina: il tag usa [WfHeroScope.source].
  /// Senza [onTap], il clic apre la scheda con il volo da qui.
  final String? heroSource;
  final double? width;

  /// Etichetta fissa sulla locandina, con il bordo oro sempre acceso: il
  /// titolo aperto nella riga della sua saga ("Questo film", spec K §8.3).
  final String? markLabel;

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
    // Unica per l'istanza della pagina (vedi WfHeroScope).
    final source = widget.heroSource;
    final heroSource =
        source == null ? null : WfHeroScope.source(context, source);
    final mark = widget.markLabel;

    final card = SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap ??
              () => openItem(context, widget.item, heroSource: heroSource),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: WfMotion.fast,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _hover || mark != null
                            ? WfColors.gold
                            : Colors.transparent,
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        WfHero(
                          tag: heroSource == null
                              ? null
                              : WfHeroTag(item.id, heroSource),
                          child: WfImage(
                              image: ref.watch(imageUrlsProvider).poster(item)),
                        ),
                        if (progress != null) ProgressStrip(progress: progress),
                        if (userData.played)
                          const Positioned(
                              top: 6, right: 6, child: WatchedBadge())
                        else if (item.kind == ItemKind.series && unplayed > 0)
                          Positioned(
                              top: 6, right: 6, child: CountBadge(count: unplayed)),
                        if (mark != null)
                          Positioned(
                              top: 6, left: 6, child: _MarkChip(label: mark)),
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
    return CardPreviewHost(item: item, heroSource: heroSource, child: card);
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
          // Senza, l'oro (che non ha figli) prende l'altezza minima che
          // l'allineamento gli lascia, cioè 0, e non si vede (issue #9).
          heightFactor: 1,
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
  const CountBadge({super.key, required this.count, this.max});

  final int count;

  /// Oltre questo numero si scrive "[max]+"; `null` = sempre il numero.
  final int? max;

  @override
  Widget build(BuildContext context) {
    final max = this.max;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: WfColors.gold, borderRadius: BorderRadius.circular(10)),
      child: Text(max != null && count > max ? '$max+' : '$count',
          style: const TextStyle(
              color: WfColors.bg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Etichetta oro in alto a sinistra della locandina.
class _MarkChip extends StatelessWidget {
  const _MarkChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: WfColors.gold, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: const TextStyle(
              color: WfColors.bg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
