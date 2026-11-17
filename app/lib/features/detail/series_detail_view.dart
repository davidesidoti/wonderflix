import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_shell.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/rating_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/sliding_underline.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/ticket_shape.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_image.dart';
import '../../ui/wf_switcher.dart';
import '../home/resume_removal.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import '../ratings/friend_ratings_row.dart';
import '../ratings/rate_panel.dart';
import '../reports/reports_banner.dart';
import '../social/social_providers.dart';
import 'detail_header.dart';
import 'detail_providers.dart';
import 'detail_rows.dart';
import 'header_parallax.dart';
import 'item_actions_menu.dart';
import 'primary_action.dart';

class SeriesDetailView extends ConsumerStatefulWidget {
  const SeriesDetailView({
    super.key,
    required this.series,
    this.initialSeasonId,
    this.controller,
    this.entranceDelay = Duration.zero,
    this.headerKey,
  });

  final JellyfinItem series;
  final String? initialSeasonId;

  /// Scroll della pagina (lo segue anche lo sfondo della scheda).
  final ScrollController? controller;

  /// Attesa prima dell'entrata scaglionata (a volo Hero finito).
  final Duration entranceDelay;

  /// Chiave della testata: nel layout stretto dice quando il titolo va
  /// nella barra (`barTitleVisible`).
  final GlobalKey? headerKey;

  @override
  ConsumerState<SeriesDetailView> createState() => _SeriesDetailViewState();
}

class _SeriesDetailViewState extends ConsumerState<SeriesDetailView> {
  String? _selectedSeasonId;

  String? _seasonToShow(List<JellyfinItem> seasons, JellyfinItem? next) {
    final ids = seasons.map((s) => s.id).toSet();
    for (final candidate in [
      _selectedSeasonId,
      widget.initialSeasonId,
      next?.seasonId,
    ]) {
      if (candidate != null && ids.contains(candidate)) return candidate;
    }
    final regular = seasons.where((s) => (s.indexNumber ?? 0) > 0);
    return (regular.isNotEmpty ? regular.first : seasons.firstOrNull)?.id;
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final next = ref.watch(seriesNextEpisodeProvider(series.id)).value;
    final primary = next == null
        ? null
        : primaryActionFor(next, watchUserData(ref, next));
    final seasons = ref.watch(seasonsProvider(series.id));
    final seasonList = seasons.value;
    final shownSeasonId = seasonList == null
        ? null
        : _seasonToShow(seasonList, next);
    final shownSeason = seasonList
        ?.where((s) => s.id == shownSeasonId)
        .firstOrNull;
    final l = AppLocalizations.of(context);

    final page = StaggerGroup(
      count: detailEntranceCount,
      delay: widget.entranceDelay,
      // A pezzi (sliver): di una stagione da 170 episodi si costruiscono
      // solo quelli vicini allo schermo.
      child: CustomScrollView(
        controller: widget.controller,
        slivers: [
          SliverToBoxAdapter(
            child: DetailHeader(
              key: widget.headerKey,
              item: series,
              primary: primary,
              controller: widget.controller,
              rated: shownSeason == null
                  ? null
                  : (
                      item: shownSeason,
                      title: '${series.name} · ${shownSeason.name}',
                    ),
            ),
          ),
          SliverToBoxAdapter(child: ReportsBanner(titleId: series.id)),
          SliverToBoxAdapter(
            child: StaggerItem(
              index: 5,
              child: WfSwitcher(
                child: seasons.when(
                  // Piccolo: la lista finta degli episodi sta sotto, al
                  // posto di quella vera (sennò la dissolvenza la abbassa).
                  loading: () => const SizedBox.shrink(key: ValueKey('loading')),
                  error: (error, _) => ErrorView(
                    key: const ValueKey('error'),
                    error: error,
                    onRetry: () => ref.invalidate(seasonsProvider(series.id)),
                  ),
                  data: (list) {
                    final seasonId = _seasonToShow(list, next);
                    if (seasonId == null) {
                      return const SizedBox.shrink(key: ValueKey('empty'));
                    }
                    final tv = FormFactor.of(context).tv;
                    final current = list
                        .where((s) => s.id == seasonId)
                        .firstOrNull;
                    // Gli stessi voti della riga sotto le schede (una lettura).
                    final ratings = current == null ||
                            !ref.watch(
                              socialAvailabilityProvider.select(
                                (f) => f.ratings,
                              ),
                            )
                        ? null
                        : ref.watch(itemRatingsProvider(current.id)).value;
                    void rate(ItemRatings r) => openRatePanel(
                      context,
                      ref,
                      RateSubject(
                        item: current!,
                        title: '${series.name} · ${current.name}',
                        mine: r.mine,
                      ),
                    );
                    return Column(
                      key: const ValueKey('data'),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _SeasonTabs(
                                seasons: list,
                                selectedId: seasonId,
                                onSelect: (id) =>
                                    setState(() => _selectedSeasonId = id),
                              ),
                            ),
                            // Il menu della stagione scelta (visto, segnalazioni).
                            // Sulla TV non c'è: la serie ha il suo "Altro".
                            if (current case final season? when !tv)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: detailCompact(context) ? 8 : 24,
                                ),
                                child: ItemActionsButton(
                                  item: season,
                                  extra: [
                                    if (ratings != null &&
                                        (ratings.canRate ||
                                            ratings.mine != null))
                                      (
                                        label: l.ratingRateSeason,
                                        onSelected: () => rate(ratings),
                                      ),
                                    (
                                      label: watchUserData(ref, season).played
                                          ? l.detailSeasonMarkUnwatched
                                          : l.detailSeasonMarkWatched,
                                      onSelected: () => unawaited(
                                        runUserDataAction(
                                          context,
                                          () => togglePlayedAndRefresh(
                                            ref,
                                            season,
                                            seriesId: series.id,
                                            seasonId: season.id,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (current != null)
                          SeasonRatingsStrip(
                            key: ValueKey(current.id),
                            season: current,
                            title: l.ratingFriendsRowSeason(current.name),
                            onRate: rate,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (seasonList == null && !seasons.hasError)
            const SliverToBoxAdapter(child: EpisodeListSkeleton(count: 2)),
          // Alla prima apertura gli episodi entrano con la scheda (elemento
          // 5): scaglionati solo cambiando stagione (spec C §9.3).
          if (shownSeasonId != null && !seasons.hasError)
            SliverStaggerItem(
              index: 5,
              sliver: _EpisodeSliver(
                seriesId: series.id,
                seasonId: shownSeasonId,
                highlightId: next?.id,
                animate: _selectedSeasonId != null,
              ),
            ),
          if (series.people.isNotEmpty)
            SliverToBoxAdapter(
              child: StaggerItem(
                index: 6,
                child: CastRow(people: series.people),
              ),
            ),
          SliverToBoxAdapter(
            child: StaggerItem(index: 7, child: SimilarRow(itemId: series.id)),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
    final scroll = widget.controller;
    // Senza controller (vista montata da sola nei test) niente titolo nella
    // barra.
    if (scroll == null) return page;
    final action = primary;
    final reduced = WfMotion.of(context).isReduced;
    final compactHeader = detailCompact(context) ? widget.headerKey : null;
    return ShellHeaderPublisher(
      controller: scroll,
      visibleAt: (offset) => barTitleVisible(
        offset,
        reduced: reduced,
        compactHeader: compactHeader,
      ),
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
  final _viewportKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _showSelected();
  }

  @override
  void didUpdateWidget(_SeasonTabs old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) _showSelected();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Porta la scheda scelta dentro la riga che scorre (solo quella: la
  /// pagina sotto non si muove, per questo non `Scrollable.ensureVisible`).
  void _showSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      final tab = _keys[widget.selectedId]?.currentContext?.findRenderObject();
      if (viewport is! RenderBox || tab is! RenderBox || !tab.hasSize) return;
      final left = tab.localToGlobal(Offset.zero, ancestor: viewport).dx;
      final right = left + tab.size.width;
      if (left >= 0 && right <= viewport.size.width) return;
      final target = (_scroll.offset +
              left -
              (viewport.size.width - tab.size.width) / 2)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      final duration = WfMotion.of(context)
          .pick(full: WfMotion.medium, reduced: Duration.zero);
      if (duration == Duration.zero) {
        _scroll.jumpTo(target);
      } else {
        unawaited(_scroll.animateTo(target,
            duration: duration, curve: WfMotion.emphasized));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedId;
    final tv = FormFactor.of(context).tv;
    final l = AppLocalizations.of(context);
    final side = detailCompact(context) ? 16.0 : 32.0;
    return Padding(
      // Il testo della scheda parte dove partono testata, striscia ed
      // episodi: il margine laterale meno l'8 della scheda.
      padding: EdgeInsets.fromLTRB(side - 8, 8, side - 8, 8),
      // La linea oro sta dentro al riquadro che scorre: va con le schede.
      child: SingleChildScrollView(
        key: _viewportKey,
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: SlidingUnderline(
          selected: selectedId,
          itemKeys: _keys,
          indicatorKey: const Key('season-indicator'),
          child: Row(
            children: [
              for (final season in widget.seasons)
                // Sulla TV il focus è del TvFocusable, non dell'InkWell.
                TvFocusable(
                  onActivate: () => widget.onSelect(season.id),
                  child: InkWell(
                    canRequestFocus: !tv,
                    onTap: () => widget.onSelect(season.id),
                    child: Container(
                      key: _keys.putIfAbsent(season.id, GlobalKey.new),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Text.rich(
                        TextSpan(
                          text: season.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: season.id == selectedId
                                ? WfColors.gold
                                : WfColors.cream,
                          ),
                          children: [
                            if (season.childCount case final count? when count > 0)
                              TextSpan(
                                text: ' · ${l.detailEpisodes(count)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 12.5,
                                  color: WfColors.creamMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Episodi che entrano scaglionati al cambio di stagione; gli altri
/// compaiono subito.
const _episodeEntranceCount = 10;

class _EpisodeSliver extends ConsumerWidget {
  const _EpisodeSliver({
    required this.seriesId,
    required this.seasonId,
    required this.highlightId,
    required this.animate,
  });

  final String seriesId;
  final String seasonId;
  final String? highlightId;

  /// Entrata scaglionata degli episodi (solo dopo un cambio di stagione).
  final bool animate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (seriesId: seriesId, seasonId: seasonId);
    return ref
        .watch(episodesProvider(key))
        .when(
          loading: () => const SliverToBoxAdapter(child: EpisodeListSkeleton()),
          error: (error, _) => SliverToBoxAdapter(
            child: ErrorView(
              error: error,
              onRetry: () => ref.invalidate(episodesProvider(key)),
            ),
          ),
          data: (episodes) {
            if (episodes.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    AppLocalizations.of(context).detailNoEpisodes,
                    style: const TextStyle(color: WfColors.creamMuted),
                  ),
                ),
              );
            }
            // Chiave per stagione: al cambio di stagione gli episodi
            // entrano scaglionati.
            return StaggerGroup(
              key: ValueKey('episodes-$seasonId'),
              play: animate,
              count: math.min(episodes.length, _episodeEntranceCount),
              child: SliverList.builder(
                itemCount: episodes.length,
                itemBuilder: (context, i) => StaggerItem(
                  index: i,
                  child: EpisodeTile(
                    episode: episodes[i],
                    highlighted: episodes[i].id == highlightId,
                  ),
                ),
              ),
            );
          },
        );
  }
}

class EpisodeTile extends ConsumerWidget {
  const EpisodeTile({
    super.key,
    required this.episode,
    this.highlighted = false,
  });

  final JellyfinItem episode;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final userData = watchUserData(ref, episode);
    final progress = userData.progress;
    final runtime = episode.runtime;
    // Data di calendario in UTC: toLocal() la sposterebbe di un giorno.
    final premiere = episode.premiereDate;
    final details = [
      ?episodeCode(episode),
      if (premiere != null)
        DateFormat('d MMM y', l.localeName).format(premiere),
      if (runtime != null) shortDuration(l, runtime),
    ].join(' · ');
    final overview = episode.overview;
    final form = FormFactor.of(context);
    final compact = detailCompact(context);
    final tv = form.tv;
    void play() => unawaited(playItem(context, ref, episode));
    final actions = [
      FilterChip(
        avatar: const Icon(LucideIcons.check, size: 16),
        showCheckmark: false,
        label: Text(l.detailActionWatched),
        selected: userData.played,
        onSelected: (_) => unawaited(
          runUserDataAction(
            context,
            () => togglePlayedAndRefresh(ref, episode),
          ),
        ),
      ),
      // Il bottone sta dentro l'InkWell, ma il tocco non ne attiva l'onTap:
      // vince il riconoscitore del bottone nell'arena.
      ItemActionsButton(
        item: episode,
        extra: [
          if (userData.playbackPositionTicks > 0)
            (
              label: l.resumeHide,
              onSelected: () =>
                  unawaited(removeFromResume(context, ref, episode)),
            ),
        ],
      ),
    ];

    final stillWidth = compact ? 120.0 : 200.0;
    // Lo strappo del biglietto come nella bozza; il testo parte 8 dopo.
    const inset = 12.0;
    final tear = compact ? 148.0 : 224.0;
    final gap = highlighted
        ? tear - inset - stillWidth + 8
        : (compact ? 12.0 : 16.0);
    // Nel biglietto il testo finisce con quanto manca, o con Riproduci.
    final position = userData.playbackPosition;
    final remaining = position > Duration.zero && runtime != null
        ? runtime - position
        : null;
    final resume = !highlighted
        ? null
        : remaining != null && remaining > Duration.zero
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.detailNextResume(shortDuration(l, remaining)),
                style: _resumeStyle,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: compact ? double.infinity : 160,
                height: 3,
                child: ProgressStrip(
                  progress: (position.inMilliseconds / runtime!.inMilliseconds)
                      .clamp(0.0, 1.0),
                ),
              ),
            ],
          )
        : Text(l.actionPlay, style: _resumeStyle);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: stillWidth,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WfImage(
                    image: ref.watch(imageUrlsProvider).landscape(episode),
                  ),
                  if (highlighted)
                    Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: WfColors.bg.withValues(alpha: 0.6),
                          border: Border.all(
                            color: WfColors.cream.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Icon(
                          LucideIcons.play,
                          size: 16,
                          color: WfColors.cream,
                        ),
                      ),
                    ),
                  if (progress != null) ProgressStrip(progress: progress),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (highlighted) ...[
                Text(
                  l.ticketNext,
                  style: const TextStyle(
                    color: WfColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                episode.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  details,
                  style: const TextStyle(
                    color: WfColors.creamMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
              if (overview != null && !compact) ...[
                const SizedBox(height: 6),
                Text(
                  overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WfColors.creamMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
              if (resume != null) ...[const SizedBox(height: 8), resume],
              if (compact) ...[
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
        if (!tv && !compact) ...actions,
        if (tv && userData.played)
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: WatchedBadge(),
          ),
      ],
    );
    final side = compact ? 16.0 : 32.0;
    final Widget tile;
    if (!highlighted) {
      tile = InkWell(
        // Sulla TV il focus è del TvFocusable, non dell'InkWell.
        canRequestFocus: !tv,
        onTap: play,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: side, vertical: 10),
          child: content,
        ),
      );
    } else {
      // Il biglietto: la still resta allineata a quelle delle altre righe.
      tile = Stack(
        children: [
          ClipPath(
            clipper: TicketClipper.vertical(tear),
            child: Material(
              color: WfColors.surface,
              child: InkWell(
                canRequestFocus: !tv,
                onTap: play,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: inset,
                    vertical: compact ? 10 : 14,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: WfColors.gold, width: 1.5),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: TicketTearPainter.vertical(tear)),
            ),
          ),
        ],
      );
      // Sulla TV l'anello del focus aderisce al biglietto, crema perché l'oro
      // del bordo non sembri già il focus.
      return Padding(
        key: const Key('next-episode-ticket'),
        padding: EdgeInsets.symmetric(horizontal: side - inset, vertical: 6),
        child: TvFocusable(
          onActivate: play,
          borderRadius: BorderRadius.circular(8),
          color: tvFocusSideOnGold.color,
          child: tile,
        ),
      );
    }
    return TvFocusable(onActivate: play, child: tile);
  }
}

const _resumeStyle = TextStyle(
  color: WfColors.cream,
  fontSize: 12.5,
  fontWeight: FontWeight.w600,
);
