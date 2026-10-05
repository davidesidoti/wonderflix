import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';

/// L'etichetta di una card "Da richiedere" (spec I §9.1).
String requestableBadge(AppLocalizations l, RequestableTitle title) =>
    switch (title.status) {
      TitleStatus.none => title.mediaType == RequestMediaType.movie
          ? l.requestsKindMovie
          : l.requestsKindSeries,
      TitleStatus.pending => l.requestsBadgeRequested,
      TitleStatus.processing => l.requestsBadgeComing,
      TitleStatus.partial => l.requestsBadgePartial,
      TitleStatus.available => l.requestsBadgeOnWonderflix,
    };

/// Locandina 2:3 di un titolo di Seerr (spec I §9.1): immagine di TMDB,
/// etichetta in alto a sinistra, titolo e anno. Come `PosterCard` ma senza
/// l'anteprima al passaggio del mouse.
class RequestablePosterCard extends StatefulWidget {
  const RequestablePosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.width = 150,
  });

  final RequestableTitle title;
  final VoidCallback onTap;
  final double width;

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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        WfImage(image: TmdbImages.poster(title.posterPath)),
                        Positioned(
                          top: 6,
                          left: 6,
                          child: RequestBadge(
                            label: requestableBadge(l, title),
                            highlighted: title.status != TitleStatus.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(title.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (year != null)
                Text('$year',
                    style: const TextStyle(
                        color: WfColors.creamMuted, fontSize: 12)),
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
