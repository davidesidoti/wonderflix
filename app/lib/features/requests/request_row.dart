import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_image.dart';
import '../inbox/inbox_time.dart';
import 'request_labels.dart';
import 'request_track.dart';

/// Una riga della pagina Richieste (spec §5.3): locandina, titolo e anno,
/// tipo o stagioni, chi l'ha chiesto, quando; a destra il percorso (richieste
/// in corso), l'etichetta di stato (le altre) o [trailing] (Approva e
/// Rifiuta).
class RequestRow extends StatelessWidget {
  const RequestRow({
    super.key,
    required this.request,
    required this.now,
    required this.onTap,
    this.showRequester = false,
    this.trailing,
  });

  /// Misure della locandina piccola (2:3), larga e stretta.
  static const posterWidth = 56.0;
  static const posterHeight = 84.0;
  static const compactPosterWidth = 40.0;
  static const compactPosterHeight = 60.0;

  /// Larghezza della colonna del percorso (fuori dallo stretto).
  static const trackWidth = 400.0;

  final MediaRequest request;

  /// Per l'ora relativa ("5 min fa").
  final DateTime now;

  /// Il clic sulla riga; `null` la blocca (Approva o Rifiuta in viaggio).
  final VoidCallback? onTap;

  /// "chiesta da {name}", nelle schede da admin.
  final bool showRequester;

  /// Al posto del percorso e dell'etichetta di stato (Approva e Rifiuta).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final factor = FormFactor.of(context);
    // La TV ha lo schermo largo anche se in dp è sotto la soglia dello stretto.
    final narrow = factor.compact && !factor.tv;
    final title = request.title.isEmpty ? l.requestsUnknownTitle : request.title;
    final year = request.year;
    final inProgress = trailing == null && requestTrackModel(request, l) != null;
    // Nello stretto il percorso e le azioni (Approva, Rifiuta) vanno sotto il
    // testo: accanto lascerebbero al titolo meno di metà schermo.
    final below = narrow && (inProgress || trailing != null);
    final Widget? side;
    if (trailing != null) {
      side = trailing;
    } else if (inProgress) {
      side = SizedBox(
        width: narrow ? null : trackWidth,
        child: RequestTrack(
            request: request, now: now, labels: factor.tv || !narrow),
      );
    } else {
      side = RequestStatusLabel(request: request);
    }
    final row = Row(
      crossAxisAlignment:
          narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: narrow ? compactPosterWidth : posterWidth,
            height: narrow ? compactPosterHeight : posterHeight,
            child: WfImage(image: TmdbImages.poster(request.posterPath)),
          ),
        ),
        SizedBox(width: narrow ? 12 : 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(year == null ? title : '$title ($year)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: narrow ? 14 : 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              _Meta(request: request, now: now, showRequester: showRequester),
            ],
          ),
        ),
        if (!below) ...[const SizedBox(width: 20), ?side],
      ],
    );
    // Sulla TV la riga è una tappa sola, con la cornice del telecomando.
    return TvFocusable(
      onActivate: onTap,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: WfColors.surface)),
        ),
        child: InkWell(
          onTap: onTap,
          hoverColor: WfColors.surfaceHigh,
          canRequestFocus: !factor.tv,
          child: Padding(
            padding: EdgeInsets.symmetric(
                vertical: narrow ? 9 : 10, horizontal: narrow ? 8 : 12),
            child: below
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row,
                      const SizedBox(height: 8),
                      if (inProgress)
                        side!
                      else
                        Align(alignment: Alignment.centerRight, child: side),
                    ],
                  )
                : row,
          ),
        ),
      ),
    );
  }
}

/// La riga sotto il titolo: tipo o stagioni, chi l'ha chiesto (con l'avatar),
/// quando.
class _Meta extends StatelessWidget {
  const _Meta(
      {required this.request, required this.now, required this.showRequester});

  final MediaRequest request;
  final DateTime now;
  final bool showRequester;

  static const _style = TextStyle(color: WfColors.creamMuted, fontSize: 13);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final seasons = request.seasons;
    final kind = request.mediaType == RequestMediaType.movie
        ? l.requestsKindMovie
        : seasons.isEmpty
            ? l.requestsKindSeries
            : l.requestsSeasonsList(seasons.length, formatSeasonList(seasons));
    final requester = request.requestedBy;
    final who = requester.isMe ? l.requestsYou : requester.name;
    // "chiesta da" e il nome sono separati dall'avatar: il prefisso è quello
    // della frase tradotta, prima del nome.
    final phrase = l.requestsRequestedBy(who);
    final prefix = phrase.substring(0, phrase.lastIndexOf(who));
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$kind · '),
        if (showRequester) ...[
          TextSpan(text: prefix),
          if (!requester.isMe)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: UserAvatar.lookup(name: requester.name, size: 18),
              ),
            ),
          TextSpan(
              text: who,
              style: requester.isMe ? null : const TextStyle(color: WfColors.cream)),
          const TextSpan(text: ' · '),
        ],
        TextSpan(text: inboxTimeLabel(request.createdAt, now, l)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _style,
    );
  }
}

/// L'etichetta dello stato, testo nel suo colore e senza bordo.
class RequestStatusLabel extends StatelessWidget {
  const RequestStatusLabel({super.key, required this.request});

  final MediaRequest request;

  @override
  Widget build(BuildContext context) => Text(
        requestStatusLabel(AppLocalizations.of(context), request),
        style: TextStyle(
            color: requestStatusColor(request.status),
            fontSize: 12.5,
            fontWeight: FontWeight.w600),
      );
}
