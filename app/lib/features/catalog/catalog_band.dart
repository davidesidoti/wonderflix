import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_image.dart';
import '../../ui/wf_switcher.dart';
import '../library/library_providers.dart';
import 'catalog_genres.dart';

/// Altezza del cartellone: 320 su desktop, 220 stretto, 160 sulla TV.
double catalogBandHeight(BuildContext context) {
  final form = FormFactor.of(context);
  return form.tv ? 160 : (form.compact ? 220 : 320);
}

/// Sulla TV la testata non resta ferma (spec §11): col focus dentro [child]
/// (la testata, o lo sliver della griglia) la pagina scorre fino a [offset]:
/// in cima per la testata, oltre cartellone e testata per la griglia.
Widget tvScrollOnFocus({
  Key? key,
  required ScrollController scroll,
  required double Function() offset,
  required Widget child,
}) => Focus(
  key: key,
  canRequestFocus: false,
  skipTraversal: true,
  // Senza Semantics: [child] può essere uno sliver.
  includeSemantics: false,
  onFocusChange: (focused) {
    if (!focused) return;
    // Dopo il frame: vince sullo scorrimento al centro di TvFocusable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final position = scroll.position;
      final target = offset().clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target == position.pixels) return;
      scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  },
  child: child,
);

/// Il primo titolo con un fondale, qualunque sia l'ordine (spec §5).
JellyfinItem? catalogBandHero(List<JellyfinItem> items) {
  for (final item in items) {
    if (item.backdropTags.isNotEmpty) return item;
  }
  return null;
}

/// "**243 film**, 211 già visti. I più votati per primi." (il conteggio in
/// grassetto crema). Senza [totals] (ancora in lettura) solo la frase
/// dell'ordine.
TextSpan catalogBandLine(
  AppLocalizations l, {
  required ItemKind kind,
  required CatalogSort sort,
  required bool reversed,
  CatalogTotals? totals,
}) {
  final series = kind == ItemKind.series;
  final order = switch (sort) {
    CatalogSort.dateAdded when series =>
      reversed ? l.catalogOrderNewEpisodesReversed : l.catalogOrderNewEpisodes,
    CatalogSort.dateAdded =>
      reversed ? l.catalogOrderAddedReversed : l.catalogOrderAdded,
    CatalogSort.title =>
      reversed ? l.catalogOrderTitleReversed : l.catalogOrderTitle,
    CatalogSort.year =>
      reversed ? l.catalogOrderYearReversed : l.catalogOrderYear,
    CatalogSort.rating =>
      reversed ? l.catalogOrderRatingReversed : l.catalogOrderRating,
  };
  if (totals == null) return TextSpan(text: '$order.');
  final count = series
      ? l.catalogBandSeries(totals.total, totals.secondary)
      : l.catalogBandMovies(totals.total, totals.secondary);
  // Il grassetto è il pezzo prima della virgola: "243 film", "138 serie".
  final comma = count.indexOf(',');
  final bold = comma < 0 ? count : count.substring(0, comma);
  return TextSpan(
    children: [
      TextSpan(
        text: bold,
        style: const TextStyle(
          color: WfColors.cream,
          fontWeight: FontWeight.w600,
        ),
      ),
      TextSpan(text: '${count.substring(bold.length)} $order.'),
    ],
  );
}

/// Il cartellone della sala: fondale del primo titolo, sfumature, [tabs] in
/// alto a sinistra, [title] grande e [line] sotto (spec §5). Cambiando
/// [hero] o [title] immagine e testo sfumano nei nuovi.
class CatalogBand extends ConsumerWidget {
  const CatalogBand({
    super.key,
    required this.title,
    required this.height,
    this.hero,
    this.line,
    this.tabs,
  });

  final String title;
  final double height;
  final JellyfinItem? hero;
  final InlineSpan? line;
  final Widget? tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = FormFactor.of(context);
    // Fuori dalla TV le schede stanno sotto la barra in alto della shell.
    final barBottom =
        (form.compact ? shellCompactBarHeight : shellBarHeight) +
        MediaQuery.paddingOf(context).top;
    final (side, tabsTop, textBottom, titleSize, lineSize, lineGap) = form.tv
        ? (24.0, 14.0, 8.0, 64.0, 12.5, 6.0)
        : form.compact
        ? (16.0, barBottom + 18, 14.0, 64.0, 12.5, 8.0)
        : (32.0, barBottom + 12, 22.0, 112.0, 14.0, 12.0);
    final image = hero == null
        ? null
        : ref.watch(imageUrlsProvider).backdrop(hero!, maxWidth: 1920);
    final line = this.line;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          WfSwitcher(
            expand: true,
            child: Stack(
              key: ValueKey((hero?.id, title)),
              fit: StackFit.expand,
              children: [
                if (image != null)
                  ExcludeSemantics(
                    child: WfImage(image: image, fallbackIcon: null),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        WfColors.bg,
                        Color(0xBF0A0A0A),
                        Color(0x1F0A0A0A),
                      ],
                      stops: [0, 0.38, 0.75],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [WfColors.bg, Color(0x000A0A0A)],
                      stops: [0, 0.55],
                    ),
                  ),
                ),
                Positioned(
                  left: side,
                  right: side,
                  bottom: textBottom,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WfText.display(
                            titleSize,
                          ).copyWith(height: 0.82, letterSpacing: 1),
                        ),
                      ),
                      if (line != null)
                        Padding(
                          padding: EdgeInsets.only(top: lineGap),
                          child: Text.rich(
                            line,
                            style: TextStyle(
                              color: WfColors.creamMuted,
                              fontSize: lineSize,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (tabs != null) Positioned(left: side, top: tabsTop, child: tabs!),
        ],
      ),
    );
  }
}
