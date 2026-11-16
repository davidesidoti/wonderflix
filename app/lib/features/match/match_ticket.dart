import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/ticket_shape.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';

const _height = 84.0;
const _radius = 8.0;

/// Sotto questa larghezza il fondale si stringe (fila dello stretto).
const _narrowWidth = 300.0;

/// Un match come biglietto (spec §5.5): fondale, strappo e matrice col nome
/// e una riga ("Film · 1h 49m", [note], o "Parte per primo" in oro se
/// [chosen]). [item] `null` (titolo che il server non dà): nome vuoto.
class MatchTicket extends ConsumerWidget {
  const MatchTicket({
    super.key,
    required this.id,
    required this.item,
    required this.chosen,
    this.note,
    this.onTap,
    this.width = 360,
  });

  final String id;
  final JellyfinItem? item;
  final bool chosen;
  final String? note;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final item = this.item;
    final image = width < _narrowWidth ? 104.0 : 150.0;
    final line = chosen ? l.matchPlaysFirst : note ?? _kindLine(l, item);
    final stub = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item?.name ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if (line.isNotEmpty)
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: chosen ? WfColors.gold : WfColors.creamMuted,
                fontWeight: chosen ? FontWeight.w600 : null,
              ),
            ),
        ],
      ),
    );
    final body = Row(
      children: [
        SizedBox(
          key: const Key('match-ticket-image'),
          width: image,
          height: _height,
          child: WfImage(
            image: item == null
                ? null
                : ref.watch(imageUrlsProvider).landscape(item),
          ),
        ),
        Expanded(child: stub),
      ],
    );
    return SizedBox(
      width: width,
      height: _height,
      child: Stack(
        children: [
          ClipPath(
            clipper: TicketClipper.vertical(image),
            child: Material(
              color: WfColors.surface,
              child: onTap == null ? body : InkWell(onTap: onTap, child: body),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: TicketTearPainter.vertical(image)),
            ),
          ),
          if (chosen)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.all(color: WfColors.gold, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "Film · 1h 49m" o "Serie · 1 stagione"; senza dati solo il tipo.
  static String _kindLine(AppLocalizations l, JellyfinItem? item) {
    if (item == null) return '';
    final runtime = item.runtime;
    final seasons = item.childCount;
    return switch (item.kind) {
      ItemKind.movie => [
        l.partyQueueMovie,
        if (runtime != null) formatRuntime(runtime),
      ].join(' · '),
      ItemKind.series => [
        l.partyQueueSeries,
        if (seasons != null) l.detailSeasons(seasons),
      ].join(' · '),
      _ => '',
    };
  }
}
