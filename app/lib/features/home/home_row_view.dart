import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/requests/tmdb_images.dart';
import '../../core/social/activity_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/card_preview.dart';
import '../../ui/form_factor.dart';
import '../../ui/landscape_card.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/remote_image_card.dart';
import '../../ui/user_avatar.dart';
import '../catalog/catalog_navigation.dart';
import '../friends/activity_labels.dart';
import '../recommendations/recommendation_dismissals.dart';
import '../recommendations/recommendation_labels.dart';
import '../requests/request_labels.dart';
import '../requests/requestable_poster_card.dart';
import '../requests/requests_navigation.dart';
import 'home_layout.dart';
import 'home_row_content.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return switch (content) {
      // Continua a guardare e Prossimi episodi stanno in `TonightRow`.
      ItemsRowContent(:final items) => _posters(_title(l), items),
      BecauseYouWatchedContent(:final sourceName, :final items) =>
        _posters(l.homeBecauseYouWatched(sourceName), items),
      RequestsRowContent(:final requests) => _row(
          l.homeMyRequests, _posterHeight, requests.length, (context, i) {
          final request = requests[i];
          final year = request.year;
          return RemoteImageCard(
            shape: RemoteCardShape.poster,
            width: rowPosterSize(context).width,
            image: TmdbImages.poster(request.posterPath),
            title: request.title,
            subtitle: year?.toString(),
            badge: RequestBadge(
                label: requestStatusLabel(l, request), highlighted: true),
            onTap: () => openRequest(context, request),
          );
        }),
      SagasRowContent(:final sagas) => _row(
          l.homeContinueSaga, _landscapeHeight, sagas.length, (context, i) {
          final saga = sagas[i];
          return LandscapeCard(
            item: saga.next,
            width: rowLandscapeSize(context).width,
            subtitle:
                l.homeSagaProgress(saga.saga.name, saga.watched, saga.total),
            onTap: () => openCollection(context, saga.saga.id),
          );
        }),
      // Serie e Film in arrivo stanno in `UpcomingWeek`.
      UpcomingSeriesRowContent() ||
      UpcomingMoviesRowContent() => const SizedBox.shrink(),
      RecommendedRowContent(:final titles) =>
        _recommended(context, ref, l, titles),
      FriendsWatchedRowContent(:final titles) => _friendsWatched(l, titles),
    };
  }

  String _title(AppLocalizations l) => switch (kind) {
        HomeRowKind.resume => l.homeContinueWatching,
        HomeRowKind.nextUp => l.homeNextUp,
        HomeRowKind.recommended => l.homeRowRecommended,
        HomeRowKind.friendsWatched => l.homeRowFriendsWatched,
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

  /// "Visti dagli amici": le facce e i nomi di chi l'ha visto sopra la
  /// locandina, sotto solo il titolo (spec §7).
  Widget _friendsWatched(AppLocalizations l, List<FriendsWatchedItem> titles) =>
      _row(l.homeRowFriendsWatched, _friendsHeight, titles.length,
          (context, i) {
        final title = titles[i];
        final width = _friendsWidth(context);
        return SizedBox(
          key: ValueKey('friends-watched-${title.item.id}'),
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Faces(title.by.take(3).toList()),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(friendsWatchedNames(l, title.by),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: WfColors.cream, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PosterCard(
                item: title.item,
                width: width,
                heroSource: 'home.${kind.id}.$i',
                catalogStyle: true,
                titleOnly: true,
              ),
            ],
          ),
        );
      });

  /// "Consigliati per te": chi l'ha consigliato sotto la locandina, i
  /// messaggi e "Non mi interessa" nell'anteprima (spec N §7.3, §7.4). I
  /// titoli tolti spariscono subito.
  Widget _recommended(BuildContext context, WidgetRef ref, AppLocalizations l,
      List<RecommendedItem> titles) {
    final dismissed = ref.watch(recommendationDismissalsProvider);
    final shown = [
      for (final title in titles)
        if (!dismissed.contains(jellyfinIdKey(title.item.id))) title,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return _row(l.homeRowRecommended, _catalogHeight, shown.length,
        (context, i) {
      final title = shown[i];
      return PosterCard(
        key: ValueKey('recommended-${title.item.id}'),
        item: title.item,
        width: rowPosterSize(context).width,
        heroSource: 'home.${kind.id}.$i',
        catalogStyle: true,
        subtitle: recommendedFrom(l, title.from),
        previewExtra: CardPreviewExtra(
          notes: recommendationNotes(l, title.from),
          dismissTooltip: l.recommendDismiss,
          onDismiss: () => unawaited(_dismiss(context, ref, title.item.id)),
        ),
      );
    });
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref, String itemId) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok =
        await ref.read(recommendationDismissalsProvider.notifier).dismiss(itemId);
    if (!ok) {
      messenger?.showSnackBar(SnackBar(content: Text(l.recommendDismissFailed)));
    }
  }

  /// Il link del titolo, per le righe che hanno una pagina (spec §9.1).
  VoidCallback? _link(BuildContext context) => switch (kind) {
        HomeRowKind.requests => () => context.go('/requests'),
        HomeRowKind.latestMovies => () => openCatalog(context, ItemKind.movie),
        HomeRowKind.latestSeries => () =>
            openCatalog(context, ItemKind.series),
        HomeRowKind.continueSaga => () =>
            openCatalog(context, ItemKind.movie, view: CatalogView.sagas),
        HomeRowKind.myList => () => context.go('/mylist'),
        _ => null,
      };

  /// Riga alta [height], con il conteggio delle card e il link se c'è.
  Widget _row(String title, double Function(BuildContext) height, int count,
          IndexedWidgetBuilder itemBuilder) =>
      Builder(
        builder: (context) => MediaRow(
          title: title,
          count: '$count',
          titleSize: 26,
          topSpacing: 28,
          onTitleTap: _link(context),
          height: height(context),
          itemCount: count,
          animateEntrance: animateEntrance,
          itemBuilder: itemBuilder,
        ),
      );

  static double _posterHeight(BuildContext context) =>
      rowPosterSize(context).rowHeight;

  static double _landscapeHeight(BuildContext context) =>
      rowLandscapeSize(context).rowHeight;

  /// Locandina del catalogo: 2:3 più le righe di testo sotto.
  static double _catalogHeight(BuildContext context) =>
      rowPosterSize(context).width * 1.5 +
      catalogCardTextHeight(MediaQuery.textScalerOf(context));

  static double _friendsWidth(BuildContext context) =>
      FormFactor.of(context).compact ? 124 : 176;

  /// Facce (o nomi) sopra, locandina, titolo su due righe.
  static double _friendsHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return math.max(_faceSize, scaler.scale(16)) +
        8 +
        _friendsWidth(context) * 1.5 +
        8 +
        scaler.scale(36);
  }

  Widget _posters(String title, List<JellyfinItem> items) =>
      _row(title, _catalogHeight, items.length, (context, i) => PosterCard(
            item: items[i],
            width: rowPosterSize(context).width,
            heroSource: 'home.${kind.id}.$i',
            catalogStyle: true,
          ));
}

const _faceSize = 22.0;

/// Le facce di chi l'ha visto, sovrapposte di 7 (la più recente sotto).
class _Faces extends StatelessWidget {
  const _Faces(this.by);

  final List<FriendWatcher> by;

  @override
  Widget build(BuildContext context) {
    const step = _faceSize - 7;
    return SizedBox(
      width: _faceSize + step * (by.length - 1),
      height: _faceSize,
      child: Stack(
        children: [
          for (final (i, friend) in by.indexed)
            Positioned(
              left: i * step,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: WfColors.bg, width: 2),
                ),
                child: UserAvatar.lookup(
                    userId: friend.userId,
                    name: friend.name,
                    size: _faceSize,
                    muted: true),
              ),
            ),
        ],
      ),
    );
  }
}
