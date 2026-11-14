import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_image.dart';
import 'requests_navigation.dart';

/// Lo scaffale di "Arrivate" (spec §5.5): locandine 112×168 fuori dallo
/// stretto, 3 per riga nello stretto.
class RequestShelf extends StatelessWidget {
  const RequestShelf({super.key, required this.requests});

  final List<MediaRequest> requests;

  static const posterWidth = 112.0;

  @override
  Widget build(BuildContext context) {
    final factor = FormFactor.of(context);
    final narrow = factor.compact && !factor.tv;
    final spacing = narrow ? 10.0 : 16.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = narrow
            ? (constraints.maxWidth - 2 * spacing) / 3
            : posterWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: narrow ? 14 : 18,
          children: [
            for (final request in requests)
              RequestShelfPoster(
                key: ValueKey('request-${request.id}'),
                request: request,
                width: width,
              ),
          ],
        );
      },
    );
  }
}

/// Una locandina dello scaffale: titolo su due righe e "Film"/"Serie" sotto;
/// apre la richiesta come le righe.
class RequestShelfPoster extends StatefulWidget {
  const RequestShelfPoster(
      {super.key, required this.request, required this.width});

  final MediaRequest request;
  final double width;

  @override
  State<RequestShelfPoster> createState() => _RequestShelfPosterState();
}

class _RequestShelfPosterState extends State<RequestShelfPoster> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final request = widget.request;
    void open() => openRequest(context, request);
    return SizedBox(
      width: widget.width,
      child: TvFocusable(
        onActivate: open,
        child: InkWell(
          onTap: open,
          canRequestFocus: !FormFactor.of(context).tv,
          onHover: (hover) =>
              setState(() => _hover = hover && !FormFactor.of(context).touch),
          // La cornice della locandina fa da segnale: niente velo.
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: WfMotion.fast,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: _hover ? WfColors.creamMuted : Colors.transparent),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: WfImage(image: TmdbImages.poster(request.posterPath)),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                  request.title.isEmpty ? l.requestsUnknownTitle : request.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
              Text(
                  request.mediaType == RequestMediaType.movie
                      ? l.requestsKindMovie
                      : l.requestsKindSeries,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
