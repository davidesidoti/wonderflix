import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import 'smooth_scroll.dart';
import 'staggered_entrance.dart';

/// Card di una riga che entrano volando (le prime visibili).
const rowEntranceCount = 8;

/// Passo tra una card e l'altra nell'entrata di una riga.
const rowEntranceStagger = Duration(milliseconds: 40);

/// Riga orizzontale con titolo e frecce (per chi usa il mouse).
class MediaRow extends StatefulWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.entranceDelay,
  });

  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Se presente, le prime card visibili entrano "volando" da destra dopo
  /// questo ritardo (spec C §8.2). `null` = nessuna entrata.
  final Duration? entranceDelay;

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scroll(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + direction * position.viewportDimension * 0.8)
        .clamp(0.0, position.maxScrollExtent);
    _controller.animateTo(target,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final delay = widget.entranceDelay;
    Widget list = ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      itemCount: widget.itemCount,
      separatorBuilder: (context, index) => const SizedBox(width: 16),
      // Senza entrata le card non si avvolgono: uno StaggerItem cercherebbe
      // il gruppo più vicino, che potrebbe essere quello della pagina.
      itemBuilder: delay == null
          ? widget.itemBuilder
          : (context, i) => StaggerItem(
                index: i,
                effect: EntranceEffect.fly,
                child: widget.itemBuilder(context, i),
              ),
    );
    if (delay != null) {
      list = StaggerGroup(
        count: rowEntranceCount,
        delay: delay,
        stagger: rowEntranceStagger,
        child: list,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Flexible(child: Text(widget.title, style: WfText.display(24))),
                const Spacer(),
                IconButton(
                  key: const Key('row-previous'),
                  onPressed: () => _scroll(-1),
                  icon: const Icon(LucideIcons.chevronLeft, color: WfColors.cream),
                ),
                IconButton(
                  key: const Key('row-next'),
                  onPressed: () => _scroll(1),
                  icon: const Icon(LucideIcons.chevronRight, color: WfColors.cream),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: widget.height,
            child: list,
          ),
        ],
      ),
    );
  }
}
