import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/image_urls.dart';
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

    // Quante stagioni si vedono, finché non si sa niente.
    String? subtitle;
    final Widget body;
    if (seasons.hasError || episodes.hasError) {
      body = QueueMessage(
        text: l.partyQueueLoadFailed,
        onRetry: () => ref
          ..invalidate(seasonsProvider(series.id))
          ..invalidate(queueSeriesEpisodesProvider(series.id)),
      );
    } else if ((seasons.value, episodes.value)
        case (final seasonList?, final episodeList?)) {
      final bySeason = _bySeason(episodeList);
      // Solo le stagioni con episodi veri.
      final visible = [
        for (final season in seasonList)
          if (bySeason[season.id] case final list? when list.isNotEmpty)
            (season, list),
      ];
      if (visible.isEmpty) {
        // Nessun episodio vero (solo mancanti): né "0 stagioni" né una lista
        // vuota, lo si dice.
        body = QueueMessage(text: l.partyQueueSeriesEmpty);
      } else {
        // Le stagioni si contano qui: la ricerca e La mia lista non danno
        // `ChildCount`.
        subtitle = l.detailSeasons(visible.length);
        body = ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            for (final (season, list) in visible)
              _SeasonRow(
                season: season,
                episodes: list,
                image: urls.poster(season) ?? urls.poster(series),
                queued: queued,
                full: full,
                onAdd: onAdd,
                onOpen: () => onOpenSeason(season),
              ),
          ],
        );
      }
    } else {
      body = const SizedBox.shrink();
    }

    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: series.name,
        subtitle: subtitle,
        onBack: onBack,
        onClose: onClose,
      ),
      body: body,
    );
  }
}

/// Una riga della vista Serie: la stagione con i suoi [episodes] veri, "N
/// episodi · M già in coda", ↳/＋ per quelli che mancano e ›.
class _SeasonRow extends StatelessWidget {
  const _SeasonRow({
    required this.season,
    required this.episodes,
    required this.image,
    required this.queued,
    required this.full,
    required this.onAdd,
    required this.onOpen,
  });

  final JellyfinItem season;
  final List<JellyfinItem> episodes;
  final ImageRef? image;

  /// Gli `ItemId` già nella coda del gruppo.
  final Set<String> queued;
  final bool full;
  final QueueAddCallback onAdd;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final remaining = [
      for (final episode in episodes)
        if (!queued.contains(episode.id)) episode,
    ];
    final already = episodes.length - remaining.length;
    return QueueItemRow(
      key: ValueKey('queue-season-${season.id}'),
      image: image,
      title: season.name,
      details: [
        l.partyQueueEpisodeCount(episodes.length),
        if (already > 0) l.partyQueueAlreadyQueuedCount(already),
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          QueueAddButtons(
            queued: remaining.isEmpty,
            full: full,
            onAdd: ({required next}) => onAdd(remaining, next: next),
          ),
          const Icon(LucideIcons.chevronRight,
              size: 18, color: WfColors.creamMuted),
        ],
      ),
      onTap: onOpen,
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
        // Il conto solo quando gli episodi sono arrivati.
        subtitle: episodes.hasValue
            ? '${series.name} · ${l.partyQueueEpisodeCount(list.length)}'
            : series.name,
        onBack: onBack,
        onClose: onClose,
      ),
      body: body,
    );
  }
}

/// "Tutta dopo" e "Tutta in coda": un'aggiunta alla volta, come
/// [QueueAddButtons]. Durante l'attesa un indicatore compare accanto al
/// pulsante premuto e nessuno dei due si ripreme; coda piena → spenti, con il
/// motivo nel suggerimento.
class _WholeSeasonButtons extends StatefulWidget {
  const _WholeSeasonButtons({required this.full, required this.onAdd});

  final bool full;
  final Future<void> Function({required bool next}) onAdd;

  /// Spazio tra il pulsante che aspetta e il suo indicatore.
  static const pendingGap = 8.0;

  @override
  State<_WholeSeasonButtons> createState() => _WholeSeasonButtonsState();
}

class _WholeSeasonButtonsState extends State<_WholeSeasonButtons> {
  /// Il pulsante che aspetta (`true` = "Tutta dopo"); `null` = nessuno.
  bool? _pendingNext;

  Future<void> _run(bool next) async {
    setState(() => _pendingNext = next);
    try {
      await widget.onAdd(next: next);
    } finally {
      if (mounted) setState(() => _pendingNext = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final enabled = !widget.full && _pendingNext == null;

    Widget slot(bool next, Widget button) {
      Widget child = button;
      if (_pendingNext == next) {
        child = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button,
            const SizedBox(width: _WholeSeasonButtons.pendingGap),
            const SizedBox.square(
              dimension: QueueAddButtons.pendingSize,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: WfColors.gold),
            ),
          ],
        );
      }
      return widget.full
          ? Tooltip(message: l.partyQueueFull(partyQueueLimit), child: child)
          : child;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        slot(
          true,
          WfButton.primary(
            label: l.partyQueueWholeSeasonNext,
            icon: LucideIcons.listStart,
            onPressed: enabled ? () => _run(true) : null,
          ),
        ),
        slot(
          false,
          WfButton.secondary(
            label: l.partyQueueWholeSeasonEnd,
            icon: LucideIcons.listPlus,
            onPressed: enabled ? () => _run(false) : null,
          ),
        ),
      ],
    );
  }
}
