import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import 'collections_logic.dart';
import 'collections_providers.dart';

/// Altezza della cella di una [SagaFanCard] larga [width]: il ventaglio è
/// quadrato, sotto nome, riga dei visti e barra (il testo segue la scala).
double sagaCardExtent(double width, TextScaler scaler) =>
    width + 12 + scaler.scale(20) + scaler.scale(17) + 10;

/// Card di una saga nella vista Saghe del catalogo (spec §9): le locandine
/// dei primi tre film a ventaglio (la centrale più alta), il nome ripulito,
/// quanti film sono visti e una barra con un tratto per film, oro se visto.
/// Finché i film ([sagaItemsProvider]) non ci sono: la locandina della saga
/// e nessuna barra. Il clic apre la pagina della saga.
class SagaFanCard extends ConsumerStatefulWidget {
  const SagaFanCard({super.key, required this.collection});

  final CollectionSummary collection;

  @override
  ConsumerState<SagaFanCard> createState() => _SagaFanCardState();
}

class _SagaFanCardState extends ConsumerState<SagaFanCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final collection = widget.collection;
    final urls = ref.watch(imageUrlsProvider);
    final items = ref.watch(sagaItemsProvider).value;
    final films = items == null ? null : sagaFilms(collection, items);
    final List<ImageRef?> posters;
    if (films == null || films.isEmpty) {
      final tag = collection.primaryImageTag;
      posters = [tag == null ? null : urls.primaryWithTag(collection.id, tag)];
    } else {
      posters = [
        for (final film in films.take(3)) urls.poster(film, maxWidth: 240),
      ];
    }
    final seen = films?.where((film) => film.userData.played).length ?? 0;
    final total = films?.length ?? 0;
    final String line;
    if (films == null || films.isEmpty) {
      line = l.collectionFilmCount(collection.size);
    } else if (seen == total) {
      line = l.sagaSeenAll(total);
    } else if (seen == 0) {
      line = l.sagaSeenNone(total);
    } else {
      line = l.sagaSeenSome(total, seen);
    }
    void open() => openCollection(context, collection.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = !FormFactor.of(context).touch),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TvFocusable(
              onActivate: open,
              child: AspectRatio(
                aspectRatio: 1,
                child: _Fan(posters: posters, open: _hover),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              cleanSagaName(collection.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12),
            ),
            if (films != null && films.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(
                  spacing: 3,
                  children: [
                    for (final film in films)
                      Expanded(
                        child: Container(
                          key: const ValueKey('saga-segment'),
                          height: 3,
                          decoration: BoxDecoration(
                            color: film.userData.played
                                ? WfColors.gold
                                : WfColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Il ventaglio, in un quadrato: locandine larghe il 59%, la centrale 5% più
/// in alto e sopra le altre (bozza: 118 px su 200). Con il mouse sopra le
/// laterali si aprono un poco.
class _Fan extends StatelessWidget {
  const _Fan({required this.posters, required this.open});

  final List<ImageRef?> posters;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        final width = side * 0.59;
        final lefts = switch (posters.length) {
          1 => const [0.205],
          2 => const [0.1, 0.31],
          _ => const [0.0, 0.205, 0.41],
        };
        final duration = WfMotion.of(context).duration(WfMotion.fast);
        Widget poster(int i) {
          final three = posters.length == 3;
          final lift = three && i == 1 ? side * 0.05 : 0.0;
          // Solo le laterali di un ventaglio di tre si aprono.
          final turn = three && open && i != 1 ? (i == 0 ? -1 : 1) : 0;
          return Positioned(
            left: lefts[i] * side,
            bottom: lift,
            width: width,
            height: width * 1.5,
            child: AnimatedSlide(
              duration: duration,
              offset: Offset(turn * 0.05, 0),
              child: AnimatedRotation(
                duration: duration,
                turns: turn * 2 / 360,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        offset: Offset(-6, 0),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: WfImage(
                      image: posters[i],
                      fallbackIcon: LucideIcons.layers,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // La centrale per ultima: sta sopra le altre.
        final order = posters.length == 3
            ? const [0, 2, 1]
            : [for (var i = 0; i < posters.length; i++) i];
        return Stack(children: [for (final i in order) poster(i)]);
      },
    );
  }
}
