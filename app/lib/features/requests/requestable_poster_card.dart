import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_image.dart';
import '../search/search_best.dart';

/// Locandina 2:3 di un titolo di Seerr (spec §8.2): immagine di TMDB, sotto
/// il titolo (col termine sottolineato), "Film · 2026" e lo stato: il
/// pulsante "Richiedi" o, se qualcuno l'ha già chiesto, una riga in oro. Come
/// `PosterCard` ma senza l'anteprima al passaggio del mouse.
class RequestablePosterCard extends StatefulWidget {
  const RequestablePosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.width = 150,
    this.term = '',
    this.autofocus = false,
  });

  /// Spazio della riga dello stato sotto anno e tipo (aria compresa).
  static const statusHeight = 32.0;

  final RequestableTitle title;
  final VoidCallback onTap;
  final double width;

  /// Il termine cercato, sottolineato nel titolo.
  final String term;

  /// Sulla TV la card prende il focus all'apertura della pagina.
  final bool autofocus;

  @override
  State<RequestablePosterCard> createState() => _RequestablePosterCardState();
}

class _RequestablePosterCardState extends State<RequestablePosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = widget.title;
    final year = title.year;
    final kind = title.mediaType == RequestMediaType.movie
        ? l.requestsKindMovie
        : l.requestsKindSeries;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = !FormFactor.of(context).touch),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TvFocusable(
                onActivate: widget.onTap,
                autofocus: widget.autofocus,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: AnimatedContainer(
                    duration: WfMotion.fast,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _hover ? WfColors.gold : Colors.transparent,
                          width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: WfImage(image: TmdbImages.poster(title.posterPath)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              highlightedName(
                  title.title,
                  widget.term,
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(year == null ? kind : '$kind · $year',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12)),
              const SizedBox(height: 6),
              _status(l, title.status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(AppLocalizations l, TitleStatus status) {
    final (icon, label) = switch (status) {
      TitleStatus.pending => (LucideIcons.check, l.requestsBadgeRequested),
      TitleStatus.processing => (LucideIcons.clock, l.requestsBadgeComing),
      TitleStatus.partial => (LucideIcons.circleDashed, l.requestsBadgePartial),
      // "Su WonderFlix" non arriva qui (`visibleRequestables`).
      TitleStatus.none || TitleStatus.available => (null, l.requestsRequest),
    };
    if (icon == null) return _RequestButton(label: label, onTap: widget.onTap);
    return Row(
      children: [
        Icon(icon, size: 14, color: WfColors.gold),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: WfColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// "+ Richiedi" piccolo col bordo oro; sulla TV si raggiunge sotto la
/// locandina.
class _RequestButton extends StatelessWidget {
  const _RequestButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onActivate: onTap,
      // Su un bordo oro il focus oro non si vedrebbe: crema.
      color: tvFocusSideOnGold.color,
      borderRadius: BorderRadius.circular(4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: WfColors.gold),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.plus, size: 14, color: WfColors.gold),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: WfColors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etichetta piccola: oro per lo stato di una richiesta, scura per il tipo.
class RequestBadge extends StatelessWidget {
  const RequestBadge({super.key, required this.label, required this.highlighted});

  final String label;
  final bool highlighted;

  /// Fondo dell'etichetta del tipo: il nero dell'app, quasi opaco.
  static const _darkFill = Color(0xCC0A0A0A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlighted ? WfColors.gold : _darkFill,
        borderRadius: BorderRadius.circular(3),
        border: highlighted ? null : Border.all(color: WfColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: highlighted ? WfColors.bg : WfColors.cream,
        ),
      ),
    );
  }
}
