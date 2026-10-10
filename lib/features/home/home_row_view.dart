import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../core/social/home_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/landscape_card.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/remote_image_card.dart';
import '../library/library_providers.dart';
import '../requests/request_labels.dart';
import '../requests/requestable_poster_card.dart';
import '../requests/requests_navigation.dart';
import '../requests/requests_providers.dart';
import 'home_layout.dart';
import 'home_row_content.dart';
import 'home_rows_logic.dart';

/// Una riga della Home (spec M §6.1, §8.3): il titolo e le card del suo
/// tipo.
class HomeRowView extends ConsumerWidget {
  const HomeRowView({
    super.key,
    required this.kind,
    required this.content,
    required this.animateEntrance,
  });

  final HomeRowKind kind;
  final HomeRowContent content;

  /// Le card volano dentro con la riga (vedi `MediaRow.animateEntrance`).
  final bool animateEntrance;

  /// Altezze delle righe di locandine e di card orizzontali.
  static const posterRowHeight = 300.0;
  static const landscapeRowHeight = 230.0;

  /// Larghezza delle locandine della libreria (come `RemoteCardShape.poster`).
  static const posterWidth = 160.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return switch (content) {
      ItemsRowContent(:final items) => kind == HomeRowKind.resume ||
              kind == HomeRowKind.nextUp
          ? _landscapes(_title(l), items)
          : _posters(_title(l), items),
      BecauseYouWatchedContent(:final sourceName, :final items) =>
        _posters(l.homeBecauseYouWatched(sourceName), items),
      RequestsRowContent(:final requests) => _row(
          l.homeMyRequests, posterRowHeight, requests.length, (context, i) {
          final request = requests[i];
          final year = request.year;
          return RemoteImageCard(
            shape: RemoteCardShape.poster,
            image: TmdbImages.poster(request.posterPath),
            title: request.title,
            subtitle: year?.toString(),
            badge: RequestBadge(
                label: requestStatusLabel(l, request), highlighted: true),
            onTap: () => openRequest(context, request),
          );
        }),
      SagasRowContent(:final sagas) => _row(
          l.homeContinueSaga, landscapeRowHeight, sagas.length, (context, i) {
          final saga = sagas[i];
          return LandscapeCard(
            item: saga.next,
            subtitle:
                l.homeSagaProgress(saga.saga.name, saga.watched, saga.total),
            onTap: () => openCollection(context, saga.saga.id),
          );
        }),
      UpcomingSeriesRowContent(:final episodes) =>
        _upcomingSeries(context, ref, l, episodes),
      UpcomingMoviesRowContent(:final movies) =>
        _upcomingMovies(ref, l, movies),
    };
  }

  String _title(AppLocalizations l) => switch (kind) {
        HomeRowKind.resume => l.homeContinueWatching,
        HomeRowKind.nextUp => l.homeNextUp,
        HomeRowKind.requests => l.homeMyRequests,
        HomeRowKind.latestMovies => l.homeLatestMovies,
        HomeRowKind.latestSeries => l.homeLatestSeries,
        // Il titolo vero ha il nome del titolo di partenza.
        HomeRowKind.becauseYouWatched => '',
        HomeRowKind.continueSaga => l.homeContinueSaga,
        HomeRowKind.upcomingSeries => l.homeUpcomingSeries,
        HomeRowKind.upcomingMovies => l.homeUpcomingMovies,
        HomeRowKind.myList => l.navMyList,
      };

  Widget _row(String title, double height, int count,
          IndexedWidgetBuilder itemBuilder) =>
      MediaRow(
        title: title,
        height: height,
        itemCount: count,
        animateEntrance: animateEntrance,
        itemBuilder: itemBuilder,
      );

  Widget _posters(String title, List<JellyfinItem> items) =>
      _row(title, posterRowHeight, items.length, (context, i) => PosterCard(
            item: items[i],
            width: posterWidth,
            heroSource: 'home.${kind.id}.$i',
          ));

  Widget _landscapes(String title, List<JellyfinItem> items) =>
      _row(title, landscapeRowHeight, items.length, (context, i) =>
          LandscapeCard(item: items[i], heroSource: 'home.${kind.id}.$i'));

  /// Sfondo: quello di Jellyfin se la serie c'è, poi quello di Sonarr, poi la
  /// locandina; clic: la scheda, poi Seerr, poi niente (spec M §8.3).
  Widget _upcomingSeries(BuildContext context, WidgetRef ref,
      AppLocalizations l, List<UpcomingEpisode> episodes) {
    final urls = ref.watch(imageUrlsProvider);
    final canRequest = ref.watch(requestsAvailableProvider);
    final now = clock.now();
    return _row(l.homeUpcomingSeries, landscapeRowHeight, episodes.length,
        (context, i) {
      final episode = episodes[i];
      final seriesId = episode.jellyfinSeriesId;
      final tmdbId = episode.tmdbId;
      final remote = episode.backdropUrl ?? episode.posterUrl;
      return RemoteImageCard(
        shape: RemoteCardShape.landscape,
        image: seriesId != null
            ? urls.backdropOf(seriesId)
            : remote == null
                ? null
                : ImageRef(remote),
        title: episode.seriesName,
        subtitle: upcomingEpisodeLabel(episode, now, l),
        onTap: seriesId != null
            ? () => openItemById(context, seriesId)
            : tmdbId != null && canRequest
                ? () => unawaited(
                    context.push(tmdbRoute(RequestMediaType.tv, tmdbId)))
                : null,
      );
    });
  }

  Widget _upcomingMovies(
      WidgetRef ref, AppLocalizations l, List<UpcomingMovie> movies) {
    final canRequest = ref.watch(requestsAvailableProvider);
    return _row(l.homeUpcomingMovies, posterRowHeight, movies.length,
        (context, i) {
      final movie = movies[i];
      final poster = movie.posterUrl;
      return RemoteImageCard(
        shape: RemoteCardShape.poster,
        image: poster == null ? null : ImageRef(poster),
        title: movie.title,
        subtitle: upcomingMovieLabel(movie, l),
        onTap: canRequest
            ? () => unawaited(context
                .push(tmdbRoute(RequestMediaType.movie, movie.tmdbId)))
            : null,
      );
    });
  }
}
