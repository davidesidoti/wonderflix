import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/motion.dart';
import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../ui/wf_image.dart';
import '../../library/item_labels.dart';
import '../../library/library_providers.dart';

/// Riga secondaria di un titolo della coda (spec H §9.2): "The Office ·
/// S2:E5 · 22m" per un episodio, "Film · 1979 · 1h 57m" per un film. Con
/// [playing] "ora" al posto della durata.
String queueRowDetails(AppLocalizations l, JellyfinItem item,
    {bool playing = false}) {
  final runtime = item.runtime;
  final parts = item.kind == ItemKind.episode
      ? [?item.seriesName, ?episodeCode(item)]
      : [l.partyQueueMovie, ?item.productionYear?.toString()];
  return [
    ...parts,
    if (playing)
      l.partyQueueNow
    else if (runtime != null)
      formatRuntime(runtime),
  ].join(' · ');
}

/// Titolo di una sezione del pannello: in oro, i già visti attenuati.
class QueueSectionTitle extends StatelessWidget {
  const QueueSectionTitle(this.title, {super.key, this.muted = false});

  final String title;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(title,
            style: WfText.display(17,
                color: muted ? WfColors.creamMuted : WfColors.gold)),
      );
}

enum QueueRowKind { watched, playing, upcoming }

/// Un titolo della coda (spec H §9.2): immagine, titolo, riga secondaria.
/// Passando sopra compaiono la maniglia (solo i prossimi) e ✕ (non sulla
/// riga in corso).
class QueueRow extends ConsumerStatefulWidget {
  const QueueRow({
    super.key,
    required this.kind,
    required this.item,
    required this.known,
    this.index,
    this.onTap,
    this.onRemove,
  });

  final QueueRowKind kind;

  /// Dettagli del titolo; `null` con [known] = non disponibile.
  final JellyfinItem? item;

  /// I dettagli sono arrivati (o si sa che non ci sono).
  final bool known;

  /// Posizione tra i prossimi, per il trascinamento.
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  static const radius = 6.0;

  /// Immagine 16:9 della riga.
  static const thumbWidth = 64.0;
  static const thumbHeight = 36.0;

  /// I titoli già visti sono attenuati.
  static const watchedOpacity = 0.5;

  /// Fondo e barra a sinistra della riga in corso.
  static const playingFill = 0.12;
  static const playingBar = 3.0;

  @override
  ConsumerState<QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends ConsumerState<QueueRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = widget.item;
    final playing = widget.kind == QueueRowKind.playing;
    final index = widget.index;
    final title =
        item?.name ?? (widget.known ? l.partyQueueUnavailable : '…');
    final details =
        item == null ? null : queueRowDetails(l, item, playing: playing);
    Widget hoverOnly(Widget child) => AnimatedOpacity(
        opacity: _hovered ? 1 : 0, duration: WfMotion.fast, child: child);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: widget.kind == QueueRowKind.upcoming && index != null
                ? hoverOnly(ReorderableDragStartListener(
                    index: index,
                    child: Tooltip(
                      message: l.partyQueueMove,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(LucideIcons.gripVertical,
                            size: 16, color: WfColors.creamMuted),
                      ),
                    ),
                  ))
                : null,
          ),
          const SizedBox(width: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: QueueRow.thumbWidth,
              height: QueueRow.thumbHeight,
              child: WfImage(
                  image: item == null
                      ? null
                      : ref.watch(imageUrlsProvider).landscape(item)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                if (details != null)
                  Text(details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          color:
                              playing ? WfColors.gold : WfColors.creamMuted)),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            child: widget.onRemove == null
                ? null
                : hoverOnly(IconButton(
                    icon: const Icon(LucideIcons.x, size: 16),
                    tooltip: l.partyQueueRemove,
                    color: WfColors.creamMuted,
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onRemove,
                  )),
          ),
        ],
      ),
    );
    final decorated = playing
        ? ClipRRect(
            borderRadius: BorderRadius.circular(QueueRow.radius),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                      color:
                          WfColors.gold.withValues(alpha: QueueRow.playingFill)),
                ),
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: QueueRow.playingBar,
                  child: ColoredBox(color: WfColors.gold),
                ),
                row,
              ],
            ),
          )
        : row;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Opacity(
        opacity:
            widget.kind == QueueRowKind.watched ? QueueRow.watchedOpacity : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(QueueRow.radius),
            hoverColor: WfColors.surfaceHigh,
            child: decorated,
          ),
        ),
      ),
    );
  }
}
