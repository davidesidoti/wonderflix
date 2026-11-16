import 'dart:math';

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
import '../l10n/gen/app_localizations.dart';
import 'card_preview.dart';
import 'card_preview_host.dart';
import 'form_factor.dart';
import 'tv_focusable.dart';
import 'wf_image.dart';

/// Altezza sotto la locandina di una card del catalogo: spazio, titolo su due
/// righe, e le due righe di una serie. Il testo segue la scala del sistema.
double catalogCardTextHeight(TextScaler scaler) => 8 + scaler.scale(76);

/// Altezza della cella del catalogo in una griglia larga [extent]: la
/// locandina cresce con la colonna, il testo no. Stessa conta di colonne di
/// `SliverGridDelegateWithMaxCrossAxisExtent` (180, spazio 16).
double catalogCellExtent(double extent, TextScaler scaler) {
  const maxWidth = 180.0, gap = 16.0;
  final columns = max(1, (extent / (maxWidth + gap)).ceil());
  final width = (extent - gap * (columns - 1)) / columns;
  return width * 1.5 + catalogCardTextHeight(scaler);
}

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
    this.openable = true,
    this.subtitle,
    this.previewExtra,
    this.autofocus = false,
    this.catalogStyle = false,
    this.titleOnly = false,
  });

  final JellyfinItem item;

  /// Al posto dell'anno, per esempio chi ha consigliato il titolo (spec N §7.3).
  final String? subtitle;

  /// Note e × dell'anteprima (la riga "Consigliati per te").
  final CardPreviewExtra? previewExtra;
  final VoidCallback? onTap;

  /// Card da cui parte il volo Hero (per esempio `home.latestMovies.3`),
  /// dentro la pagina: il tag usa [WfHeroScope.source].
  /// Senza [onTap], il clic apre la scheda con il volo da qui.
  final String? heroSource;
  final double? width;

  /// Sulla TV la card prende il focus all'apertura della pagina.
  final bool autofocus;

  /// Card del catalogo Film/Serie (spec catalogo §8): titolo su due righe,
  /// anno e voto, stato e episodi delle serie, locandina vista un po' spenta,
  /// niente numero oro.
  final bool catalogStyle;

  /// Sotto la locandina solo il titolo (Visti dagli amici: chi l'ha visto
  /// sta sopra).
  final bool titleOnly;

  /// Etichetta fissa sulla locandina, con il bordo oro sempre acceso: il
  /// titolo aperto nella riga della sua saga ("Questo film", spec K §8.3).
  final String? markLabel;

  /// Con `false` la card non apre niente: né il clic ([onTap] compreso), né
  /// l'anteprima al passaggio del mouse, e il cursore resta normale. Serve al
  /// titolo già aperto, nella riga della sua saga.
  final bool openable;

  @override
  ConsumerState<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<PosterCard> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final userData = watchUserData(ref, item);
    final progress = userData.progress;
    final unplayed = userData.unplayedItemCount ?? 0;
    final catalog = widget.catalogStyle;
    final series = item.kind == ItemKind.series;
    final line = widget.titleOnly
        ? null
        : widget.subtitle ??
        (catalog ? _catalogLine(AppLocalizations.of(context), item) : item.productionYear?.toString());
    // Spenta finché il mouse o il focus non la riaccendono.
    final dimmed = catalog && userData.played && !_hover && !_focused;
    // Unica per l'istanza della pagina (vedi WfHeroScope).
    final source = widget.heroSource;
    final heroSource =
        source == null ? null : WfHeroScope.source(context, source);
    final mark = widget.markLabel;
    final openable = widget.openable;
    final VoidCallback? activate = !openable
        ? null
        : widget.onTap ??
            () => openItem(context, widget.item, heroSource: heroSource);

    final card = SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: openable ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = !FormFactor.of(context).touch),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: activate,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TvFocusable(
                onActivate: activate,
                autofocus: widget.autofocus,
                onFocusChange: catalog
                    ? (focused) => setState(() => _focused = focused)
                    : null,
                child: AspectRatio(
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
                        _dim(
                          catalog,
                          dimmed,
                          WfHero(
                            tag: heroSource == null
                                ? null
                                : WfHeroTag(item.id, heroSource),
                            child: WfImage(
                                image:
                                    ref.watch(imageUrlsProvider).poster(item)),
                          ),
                        ),
                        if (progress != null) ProgressStrip(progress: progress),
                        if (userData.played)
                          const Positioned(
                              top: 6, right: 6, child: WatchedBadge())
                        else if (!catalog && series && unplayed > 0)
                          Positioned(
                              top: 6, right: 6, child: CountBadge(count: unplayed)),
                        if (mark != null)
                          Positioned(top: 6, left: 6, child: _GoldPill(mark)),
                      ],
                    ),
                  ),
                ),
                ),
              ),
              const SizedBox(height: 8),
              Text(item.name,
                  maxLines: catalog ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (line != null)
                Text(line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: catalog &&
                                series &&
                                item.status == 'Continuing' &&
                                widget.subtitle == null
                            ? WfColors.gold
                            : WfColors.creamMuted,
                        fontSize: 12)),
              if (catalog && series && !widget.titleOnly)
                _episodesLine(context, userData.played, unplayed),
            ],
          ),
        ),
      ),
    );
    // Una card che non si apre non ha neanche l'anteprima.
    return openable
        ? CardPreviewHost(
            item: item,
            heroSource: heroSource,
            extra: widget.previewExtra,
            child: card)
        : card;
  }
}

/// Seconda riga del catalogo: film "2014  ★ 8.5", serie "In corso" o
/// "2008–2013" (solo l'inizio senza fine, o con la fine nello stesso anno).
String? _catalogLine(AppLocalizations l, JellyfinItem item) {
  final year = item.productionYear;
  if (item.kind == ItemKind.series) {
    if (item.status == 'Continuing') return l.catalogSeriesContinuing;
    final end = item.endDate?.year;
    if (year == null || end == null || end == year) return year?.toString();
    return '$year–$end';
  }
  final rating = item.communityRating;
  if (year == null) return null;
  return rating == null ? '$year' : '$year  ★ ${rating.toStringAsFixed(1)}';
}

/// Terza riga delle serie: episodi da vedere, o "Vista tutta".
Widget _episodesLine(BuildContext context, bool played, int unplayed) {
  final l = AppLocalizations.of(context);
  final text = unplayed > 0
      ? l.catalogSeriesToWatch(unplayed)
      : played
          ? l.catalogSeriesAllWatched
          : null;
  if (text == null) return const SizedBox.shrink();
  return Text(text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: WfColors.creamMuted, fontSize: 12));
}

/// Nel catalogo il filtro c'è sempre (neutro se la locandina è accesa):
/// così il passaggio del mouse non rimonta l'immagine.
Widget _dim(bool catalog, bool dimmed, Widget child) => catalog
    ? ColorFiltered(
        colorFilter:
            ColorFilter.matrix(dimmed ? _Dimmed._matrix : _Dimmed._identity),
        child: child)
    : child;

/// Saturazione 55% e luminosità 80% sulla locandina vista.
abstract final class _Dimmed {
  static const _identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static const _lum = [0.2126, 0.7152, 0.0722];
  static const _sat = 0.55;
  static const _bright = 0.8;

  // Righe R, G, B: saturazione sui pesi di luminanza, poi luminosità.
  static final _matrix = <double>[
    for (var i = 0; i < 3; i++) ...[
      for (var j = 0; j < 3; j++)
        _bright * (_lum[j] * (1 - _sat) + (i == j ? _sat : 0)),
      0,
      0,
    ],
    0, 0, 0, 1, 0,
  ];
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
    return _GoldPill(max != null && count > max ? '$max+' : '$count');
  }
}

/// Pillola oro con un testo breve: il conteggio ([CountBadge]) e l'etichetta
/// fissa ([PosterCard.markLabel]) della locandina.
class _GoldPill extends StatelessWidget {
  const _GoldPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: WfColors.gold, borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: const TextStyle(
              color: WfColors.bg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
