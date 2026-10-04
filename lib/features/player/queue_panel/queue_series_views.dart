import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/syncplay/syncplay_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../ui/wf_buttons.dart';
import '../../detail/detail_providers.dart';
import '../../library/item_labels.dart';
import '../../library/library_providers.dart';
import '../../watch_party/party_queue_rules.dart';
import 'queue_add_view.dart';
import 'queue_add_widgets.dart';
import 'queue_panel_state.dart';

/// Gli episodi di [episodes] per stagione, nell'ordine dato.
Map<String, List<JellyfinItem>> _bySeason(List<JellyfinItem> episodes) {
  final seasons = <String, List<JellyfinItem>>{};
  for (final episode in episodes) {
    final seasonId = episode.seasonId;
    if (seasonId != null) (seasons[seasonId] ??= []).add(episode);
  }
  return seasons;
}

/// La vista Serie (spec H §9.2): una riga per stagione con episodi veri, con
/// ↳/＋ per tutta la stagione (gli episodi già in coda si saltano) e ›.
class QueueSeriesView extends ConsumerWidget {
  const QueueSeriesView({
    super.key,
    required this.series,
    required this.queue,
    required this.onAdd,
    required this.onOpenSeason,
    required this.onBack,
    required this.onClose,
  });

  final JellyfinItem series;
  final PlayQueue queue;
  final QueueAddCallback onAdd;
  final ValueChanged<JellyfinItem> onOpenSeason;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final seasons = ref.watch(seasonsProvider(series.id));
    final episodes = ref.watch(queueSeriesEpisodesProvider(series.id));
    final queued = partyQueueQueuedIds(queue);
    final full = partyQueueRoom(queue) == 0;
    final count = series.childCount;

    final Widget body;
    if (seasons.hasError || episodes.hasError) {
      body = QueueMessage(
        text: l.partyQueueLoadFailed,
        onRetry: () => ref
          ..invalidate(seasonsProvider(series.id))
          ..invalidate(queueSeriesEpisodesProvider(series.id)),
      );
    } else if (seasons.value case final seasonList?
        when episodes.value != null) {
      final bySeason = _bySeason(episodes.value!);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          for (final season in seasonList)
            if (bySeason[season.id] case final list? when list.isNotEmpty)
              () {
                final remaining = [
                  for (final episode in list)
                    if (!queued.contains(episode.id)) episode,
                ];
                final already = list.length - remaining.length;
                return QueueItemRow(
                  key: ValueKey('queue-season-${season.id}'),
                  image: urls.poster(season) ?? urls.poster(series),
                  title: season.name,
                  details: [
                    l.partyQueueEpisodeCount(list.length),
                    if (already > 0) l.partyQueueAlreadyQueuedCount(already),
                  ].join(' · '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QueueAddButtons(
                        queued: remaining.isEmpty,
                        full: full,
                        onAdd: ({required next}) =>
                            onAdd(remaining, next: next),
                      ),
                      const Icon(LucideIcons.chevronRight,
                          size: 18, color: WfColors.creamMuted),
                    ],
                  ),
                  onTap: () => onOpenSeason(season),
                );
              }(),
        ],
      );
    } else {
      body = const SizedBox.shrink();
    }

    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: series.name,
        subtitle: count == null ? null : l.detailSeasons(count),
        onBack: onBack,
        onClose: onClose,
      ),
      body: body,
    );
  }
}

/// La vista Stagione (spec H §9.2): "Tutta dopo" e "Tutta in coda" in alto,
/// poi un episodio per riga.
class QueueSeasonView extends ConsumerWidget {
  const QueueSeasonView({
    super.key,
    required this.series,
    required this.season,
    required this.queue,
    required this.onAdd,
    required this.onBack,
    required this.onClose,
  });

  final JellyfinItem series;
  final JellyfinItem season;
  final PlayQueue queue;
  final QueueAddCallback onAdd;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final episodes = ref.watch(queueSeriesEpisodesProvider(series.id));
    final queued = partyQueueQueuedIds(queue);
    final full = partyQueueRoom(queue) == 0;
    final list = _bySeason(episodes.value ?? const [])[season.id] ?? const [];
    final remaining = [
      for (final episode in list)
        if (!queued.contains(episode.id)) episode,
    ];

    final Widget body;
    if (episodes.hasError) {
      body = QueueMessage(
        text: l.partyQueueLoadFailed,
        onRetry: () => ref.invalidate(queueSeriesEpisodesProvider(series.id)),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          if (remaining.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _WholeSeasonButtons(
                full: full,
                onAdd: ({required next}) => onAdd(remaining, next: next),
              ),
            ),
          for (final episode in list)
            QueueItemRow(
              key: ValueKey('queue-episode-${episode.id}'),
              image: urls.landscape(episode),
              landscape: true,
              title: episode.indexNumber == null
                  ? episode.name
                  : l.partyQueueEpisodeTitle(
                      episode.indexNumber!, episode.name),
              details: episode.runtime == null
                  ? null
                  : formatRuntime(episode.runtime!),
              trailing: QueueAddButtons(
                queued: queued.contains(episode.id),
                full: full,
                onAdd: ({required next}) => onAdd([episode], next: next),
              ),
            ),
        ],
      );
    }

    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: season.name,
        subtitle: '${series.name} · ${l.partyQueueEpisodeCount(list.length)}',
        onBack: onBack,
        onClose: onClose,
      ),
      body: body,
    );
  }
}

/// "Tutta dopo" e "Tutta in coda": un'aggiunta alla volta, come
/// [QueueAddButtons].
class _WholeSeasonButtons extends StatefulWidget {
  const _WholeSeasonButtons({required this.full, required this.onAdd});

  final bool full;
  final Future<void> Function({required bool next}) onAdd;

  @override
  State<_WholeSeasonButtons> createState() => _WholeSeasonButtonsState();
}

class _WholeSeasonButtonsState extends State<_WholeSeasonButtons> {
  bool _pending = false;

  Future<void> _run(bool next) async {
    setState(() => _pending = true);
    try {
      await widget.onAdd(next: next);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final enabled = !widget.full && !_pending;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        WfButton.primary(
          label: l.partyQueueWholeSeasonNext,
          icon: LucideIcons.listStart,
          onPressed: enabled ? () => _run(true) : null,
        ),
        WfButton.secondary(
          label: l.partyQueueWholeSeasonEnd,
          icon: LucideIcons.listPlus,
          onPressed: enabled ? () => _run(false) : null,
        ),
      ],
    );
  }
}
