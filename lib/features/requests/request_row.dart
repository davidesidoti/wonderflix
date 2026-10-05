import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../inbox/inbox_time.dart';
import 'request_labels.dart';

/// Una riga della pagina Richieste (spec I §9.4): locandina, titolo e anno,
/// tipo o stagioni, chi l'ha chiesto, quando, e a destra lo stato (o
/// [trailing]).
class RequestRow extends StatelessWidget {
  const RequestRow({
    super.key,
    required this.request,
    required this.now,
    required this.onTap,
    this.showRequester = false,
    this.trailing,
  });

  /// Misure della locandina piccola (2:3).
  static const posterWidth = 46.0;
  static const posterHeight = 69.0;

  final MediaRequest request;

  /// Per l'ora relativa ("5 min fa").
  final DateTime now;
  final VoidCallback onTap;

  /// "chiesto da {name}", nelle schede da admin.
  final bool showRequester;

  /// Al posto dell'etichetta di stato (Approva e Rifiuta).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = request.title.isEmpty ? l.requestsUnknownTitle : request.title;
    final year = request.year;
    final seasons = request.seasons;
    final details = [
      if (request.mediaType == RequestMediaType.movie)
        l.requestsKindMovie
      else if (seasons.isEmpty)
        l.requestsKindSeries
      else
        l.requestsSeasonsList(seasons.length, formatSeasonList(seasons)),
      if (showRequester) l.requestsRequestedBy(request.requestedBy.name),
      inboxTimeLabel(request.createdAt, now, l),
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: posterWidth,
                height: posterHeight,
                child: WfImage(image: TmdbImages.poster(request.posterPath)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(year == null ? title : '$title ($year)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ?? RequestStatusLabel(request: request),
          ],
        ),
      ),
    );
  }
}

/// L'etichetta dello stato, con il bordo e il testo del suo colore.
class RequestStatusLabel extends StatelessWidget {
  const RequestStatusLabel({super.key, required this.request});

  final MediaRequest request;

  @override
  Widget build(BuildContext context) {
    final color = requestStatusColor(request.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        requestStatusLabel(AppLocalizations.of(context), request),
        style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
