import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'detail_header.dart';
import 'detail_providers.dart';
import 'detail_rows.dart';
import 'primary_action.dart';

class SeriesDetailView extends ConsumerStatefulWidget {
  const SeriesDetailView({super.key, required this.series, this.initialSeasonId});

  final JellyfinItem series;
  final String? initialSeasonId;

  @override
  ConsumerState<SeriesDetailView> createState() => _SeriesDetailViewState();
}

class _SeriesDetailViewState extends ConsumerState<SeriesDetailView> {
  String? _selectedSeasonId;

  String? _seasonToShow(List<JellyfinItem> seasons, JellyfinItem? next) {
    final ids = seasons.map((s) => s.id).toSet();
    for (final candidate in [_selectedSeasonId, widget.initialSeasonId, next?.seasonId]) {
      if (candidate != null && ids.contains(candidate)) return candidate;
    }
    final regular = seasons.where((s) => (s.indexNumber ?? 0) > 0);
    return (regular.isNotEmpty ? regular.first : seasons.firstOrNull)?.id;
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final next = ref.watch(seriesNextEpisodeProvider(series.id)).value;
    final primary = next == null ? null : primaryActionFor(next, watchUserData(ref, next));
    final seasons = ref.watch(seasonsProvider(series.id));

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        DetailHeader(item: series, primary: primary),
        seasons.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(32), child: LoadingView()),
          error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(seasonsProvider(series.id))),
          data: (list) {
            final seasonId = _seasonToShow(list, next);
            if (seasonId == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SeasonTabs(
                  seasons: list,
                  selectedId: seasonId,
                  onSelect: (id) => setState(() => _selectedSeasonId = id),
                ),
                _EpisodeList(
                    seriesId: series.id, seasonId: seasonId, highlightId: next?.id),
              ],
            );
          },
        ),
        if (series.people.isNotEmpty) CastRow(people: series.people),
        SimilarRow(itemId: series.id),
      ],
    );
  }
}

class _SeasonTabs extends StatelessWidget {
  const _SeasonTabs({
    required this.seasons,
    required this.selectedId,
    required this.onSelect,
  });

  final List<JellyfinItem> seasons;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Wrap(
        children: [
          for (final season in seasons)
            InkWell(
              onTap: () => onSelect(season.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: season.id == selectedId
                          ? WfColors.gold
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  season.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: season.id == selectedId ? WfColors.gold : WfColors.cream,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EpisodeList extends ConsumerWidget {
  const _EpisodeList({
    required this.seriesId,
    required this.seasonId,
    required this.highlightId,
  });

  final String seriesId;
  final String seasonId;
  final String? highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (seriesId: seriesId, seasonId: seasonId);
    return ref.watch(episodesProvider(key)).when(
          loading: () =>
              const Padding(padding: EdgeInsets.all(32), child: LoadingView()),
          error: (error, _) => ErrorView(
              error: error, onRetry: () => ref.invalidate(episodesProvider(key))),
          data: (episodes) {
            if (episodes.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Text(AppLocalizations.of(context).detailNoEpisodes,
                    style: const TextStyle(color: WfColors.creamMuted)),
              );
            }
            return Column(
              children: [
                for (final episode in episodes)
                  EpisodeTile(
                      episode: episode, highlighted: episode.id == highlightId),
              ],
            );
          },
        );
  }
}

class EpisodeTile extends ConsumerWidget {
  const EpisodeTile({super.key, required this.episode, this.highlighted = false});

  final JellyfinItem episode;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final userData = watchUserData(ref, episode);
    final progress = userData.progress;
    final runtime = episode.runtime;
    final index = episode.indexNumber;
    final details = [
      if (runtime != null) formatRuntime(runtime),
      if (progress != null && runtime != null)
        l.detailRemaining(formatRuntime(runtime - userData.playbackPosition)),
    ].join(' · ');
    final overview = episode.overview;

    return InkWell(
      onTap: () => unawaited(playItem(context, ref, episode)),
      child: Container(
        color: highlighted ? WfColors.surface : null,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      WfImage(image: ref.watch(imageUrlsProvider).landscape(episode)),
                      if (progress != null) ProgressStrip(progress: progress),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(index == null ? episode.name : '$index. ${episode.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(details,
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 12.5)),
                  ],
                  if (overview != null) ...[
                    const SizedBox(height: 6),
                    Text(overview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 12.5, height: 1.4)),
                  ],
                ],
              ),
            ),
            if (userData.played)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: WatchedBadge(),
              ),
          ],
        ),
      ),
    );
  }
}
