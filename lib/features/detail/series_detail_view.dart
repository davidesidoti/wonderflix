import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/sliding_underline.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../../ui/wf_switcher.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'detail_header.dart';
import 'detail_providers.dart';
import 'detail_rows.dart';
import 'header_parallax.dart';
import 'primary_action.dart';

class SeriesDetailView extends ConsumerStatefulWidget {
  const SeriesDetailView({
    super.key,
    required this.series,
    this.initialSeasonId,
    this.controller,
    this.entranceDelay = Duration.zero,
  });

  final JellyfinItem series;
  final String? initialSeasonId;

  /// Scroll della pagina (lo segue anche lo sfondo della scheda).
  final ScrollController? controller;

  /// Attesa prima dell'entrata scaglionata (a volo Hero finito).
  final Duration entranceDelay;

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

    final page = StaggerGroup(
      count: detailEntranceCount,
      delay: widget.entranceDelay,
      child: ListView(
        controller: widget.controller,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          DetailHeader(
              item: series, primary: primary, controller: widget.controller),
          StaggerItem(
            index: 5,
            child: WfSwitcher(
              child: seasons.when(
                loading: () => const EpisodeListSkeleton(
                    key: ValueKey('loading'), count: 2),
                error: (error, _) => ErrorView(
                    key: const ValueKey('error'),
                    error: error,
                    onRetry: () => ref.invalidate(seasonsProvider(series.id))),
                data: (list) {
                  final seasonId = _seasonToShow(list, next);
                  if (seasonId == null) {
                    return const SizedBox.shrink(key: ValueKey('empty'));
                  }
                  return Column(
                    key: const ValueKey('data'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SeasonTabs(
                        seasons: list,
                        selectedId: seasonId,
                        onSelect: (id) =>
                            setState(() => _selectedSeasonId = id),
                      ),
                      _EpisodeList(
                          seriesId: series.id,
                          seasonId: seasonId,
                          highlightId: next?.id),
                    ],
                  );
                },
              ),
            ),
          ),
          if (series.people.isNotEmpty)
            StaggerItem(index: 6, child: CastRow(people: series.people)),
          StaggerItem(index: 7, child: SimilarRow(itemId: series.id)),
        ],
      ),
    );
    final scroll = widget.controller;
    // Senza controller (vista montata da sola nei test) niente titolo nella
    // barra.
    if (scroll == null) return page;
    final l = AppLocalizations.of(context);
    final action = primary;
    final reduced = WfMotion.of(context).isReduced;
    return ShellHeaderPublisher(
      controller: scroll,
      visibleAt: (offset) => barTitleVisible(offset, reduced: reduced),
      header: ShellHeader(
        title: series.name,
        actionLabel: action == null ? null : primaryActionLabel(l, action),
        onAction: action == null
            ? null
            : () => unawaited(playItem(context, ref, action.target)),
      ),
      child: page,
    );
  }
}

class _SeasonTabs extends StatefulWidget {
  const _SeasonTabs({
    required this.seasons,
    required this.selectedId,
    required this.onSelect,
  });

  final List<JellyfinItem> seasons;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<_SeasonTabs> createState() => _SeasonTabsState();
}

/// Stagioni con la linea oro che scorre sotto quella scelta (spec C §9.3).
class _SeasonTabsState extends State<_SeasonTabs> {
  final _keys = <Object, GlobalKey>{};

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: SlidingUnderline(
        selected: selectedId,
        itemKeys: _keys,
        indicatorKey: const Key('season-indicator'),
        child: Wrap(
          children: [
            for (final season in widget.seasons)
              InkWell(
                onTap: () => widget.onSelect(season.id),
                child: Container(
                  key: _keys.putIfAbsent(season.id, GlobalKey.new),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    season.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: season.id == selectedId
                          ? WfColors.gold
                          : WfColors.cream,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Episodi che entrano scaglionati al cambio di stagione; gli altri
/// compaiono subito.
const _episodeEntranceCount = 10;

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
    // Chiavi per stagione: al cambio di stagione c'è una dissolvenza
    // incrociata e poi gli episodi entrano scaglionati.
    final (state, content) = ref.watch(episodesProvider(key)).when(
          loading: () => ('loading', const EpisodeListSkeleton()),
          error: (error, _) => (
            'error',
            ErrorView(
                error: error,
                onRetry: () => ref.invalidate(episodesProvider(key))),
          ),
          data: (episodes) {
            if (episodes.isEmpty) {
              return (
                'empty',
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(AppLocalizations.of(context).detailNoEpisodes,
                      style: const TextStyle(color: WfColors.creamMuted)),
                ),
              );
            }
            return (
              'data',
              StaggerGroup(
                key: ValueKey('episodes-$seasonId'),
                count: math.min(episodes.length, _episodeEntranceCount),
                child: Column(children: [
                  for (final (i, episode) in episodes.indexed)
                    StaggerItem(
                      index: i,
                      child: EpisodeTile(
                          episode: episode,
                          highlighted: episode.id == highlightId),
                    ),
                ]),
              ),
            );
          },
        );
    return WfSwitcher(
      child: KeyedSubtree(key: ValueKey('$seasonId-$state'), child: content),
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
