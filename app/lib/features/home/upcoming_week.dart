import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/requests/remote_images.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/home_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/media_row.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_image.dart';
import '../calendar/calendar_navigation.dart';
import '../library/library_providers.dart';
import '../requests/requests_navigation.dart';
import '../requests/requests_providers.dart';
import 'home_sections.dart';

/// Testa di un giorno: il numero in Bebas 44 e lo spazio sotto.
const _headHeight = 44.0, _headGap = 10.0;

/// Immagine di un episodio (16:9) e locandina di un film (2:3).
const _episodeThumb = Size(96, 54), _moviePoster = Size(40, 60);

/// Aria sopra e sotto ogni uscita.
const _entryPadding = 6.0;

/// "In arrivo" (spec §8): le uscite di Serie in arrivo e Film in arrivo, una
/// colonna per giorno, dal più vicino.
class UpcomingWeek extends ConsumerWidget {
  const UpcomingWeek({
    super.key,
    required this.episodes,
    required this.movies,
    required this.animateEntrance,
  });

  final List<UpcomingEpisode> episodes;
  final List<UpcomingMovie> movies;

  /// Vedi `MediaRow.animateEntrance`.
  final bool animateEntrance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final days = upcomingDays(episodes: episodes, movies: movies);
    if (days.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    // Titolo e riga sotto (12,5 e 11,5) accanto all'immagine.
    final text = scaler.scale(32);
    double entryHeight(UpcomingEntry e) =>
        2 * _entryPadding +
        math.max(
          text,
          (e is UpcomingEpisodeEntry ? _episodeThumb : _moviePoster).height,
        );
    // Le colonne sono alte come la più lunga: la linea tra i giorni arriva
    // in fondo.
    final height =
        scaler.scale(_headHeight) +
        _headGap +
        days
            .map((d) => d.entries.map(entryHeight).fold(0.0, (a, b) => a + b))
            .reduce(math.max);
    final count = days.fold(0, (n, d) => n + d.entries.length);
    final now = clock.now();
    return MediaRow(
      title: l.homeUpcoming,
      count: l.homeUpcomingCount(count),
      titleSize: 26,
      topSpacing: 28,
      onTitleTap: () => openCalendarWeek(context),
      height: height,
      itemCount: days.length,
      animateEntrance: animateEntrance,
      itemBuilder: (context, i) => _DayColumn(
        key: ValueKey(
          'upcoming-day-${days[i].day.toIso8601String().substring(0, 10)}',
        ),
        day: days[i],
        note: upcomingDayNote(days[i].day, now, l),
        last: i == days.length - 1,
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    super.key,
    required this.day,
    required this.note,
    required this.last,
  });

  final UpcomingDay day;
  final String? note;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final note = this.note;
    final date = day.day;
    final weekday = DateFormat.E(l.localeName).format(date);
    final month = DateFormat.MMM(l.localeName).format(date);
    return Container(
      width: FormFactor.of(context).compact ? 200 : 236,
      padding: const EdgeInsets.only(right: 16),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(right: BorderSide(color: WfColors.surface)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${date.day}',
                style: WfText.display(
                  44,
                  color: note != null ? WfColors.gold : WfColors.cream,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$weekday $month',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WfText.display(18, color: WfColors.creamMuted),
                ),
              ),
              // Con la nota, giorno e nota si dividono lo spazio: nessuno dei
              // due spinge l'altro fuori dalla colonna.
              if (note != null)
                Expanded(
                  child: Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: WfColors.gold,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: _headGap),
          for (final entry in day.entries) _Entry(entry),
        ],
      ),
    );
  }
}

/// Un'uscita: immagine, titolo e codice dell'episodio o "Film, in digitale".
/// Clic: la scheda se il titolo è in
/// libreria, poi Seerr, poi niente.
class _Entry extends ConsumerWidget {
  const _Entry(this.entry);

  final UpcomingEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final canRequest = ref.watch(requestsAvailableProvider);
    final (title, line, thumb, image, onTap) = switch (entry) {
      UpcomingEpisodeEntry(:final episode) => (
        episode.seriesName,
        upcomingEpisodeCode(episode),
        _episodeThumb,
        _episodeImage(ref, episode),
        _episodeTap(context, episode, canRequest),
      ),
      UpcomingMovieEntry(:final movie) => (
        movie.title,
        l.homeUpcomingMovie,
        _moviePoster,
        movie.posterUrl == null ? null : RemoteImages.poster(movie.posterUrl!),
        _movieTap(context, movie, canRequest),
      ),
    };
    return TvFocusable(
      key: const Key('upcoming-entry'),
      onActivate: onTap,
      borderRadius: BorderRadius.circular(4),
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: _entryPadding),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox.fromSize(
                    size: thumb,
                    child: WfImage(image: image, fallbackIcon: null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: WfColors.creamMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Il fondale di Jellyfin se la serie c'è, poi quello di Sonarr, poi la
  /// locandina.
  static ImageRef? _episodeImage(WidgetRef ref, UpcomingEpisode episode) {
    final seriesId = episode.jellyfinSeriesId;
    if (seriesId != null) {
      return ref.watch(imageUrlsProvider).backdropOf(seriesId);
    }
    final remote = episode.backdropUrl ?? episode.posterUrl;
    return remote == null ? null : RemoteImages.backdrop(remote);
  }

  static VoidCallback? _episodeTap(
    BuildContext context,
    UpcomingEpisode episode,
    bool canRequest,
  ) {
    final seriesId = episode.jellyfinSeriesId;
    final tmdbId = episode.tmdbId;
    if (seriesId != null) return () => openItemById(context, seriesId);
    if (tmdbId != null && canRequest) {
      return () =>
          unawaited(context.push(tmdbRoute(RequestMediaType.tv, tmdbId)));
    }
    return null;
  }

  /// La scheda se il film è in libreria, poi Seerr, poi niente (spec §8.2).
  static VoidCallback? _movieTap(
    BuildContext context,
    UpcomingMovie movie,
    bool canRequest,
  ) {
    final itemId = movie.jellyfinItemId;
    if (itemId != null) return () => openItemById(context, itemId);
    if (!canRequest) return null;
    return () => unawaited(
      context.push(tmdbRoute(RequestMediaType.movie, movie.tmdbId)),
    );
  }
}
