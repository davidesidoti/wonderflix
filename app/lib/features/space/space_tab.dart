import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/space/space_api.dart';
import '../../core/space/space_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../admin/admin_action_button.dart';
import '../admin/admin_poller.dart';
import '../admin/admin_time.dart';
import '../admin/admin_widgets.dart';
import '../downloads/download_search_page.dart';
import 'space_actions.dart';
import 'space_controller.dart';
import 'space_labels.dart';
import 'space_rows.dart';
import 'space_title_dialog.dart';

/// Righe per sezione, e quante ne aggiunge "Mostra altri" (decisione 1).
const _pageSize = 20;

/// La scheda Spazio (spec U §8): la quota e le liste per liberare spazio.
class SpaceTab extends ConsumerStatefulWidget {
  const SpaceTab({super.key, this.header});

  /// La striscia del server, nel layout stretto.
  final Widget? header;

  @override
  ConsumerState<SpaceTab> createState() => _SpaceTabState();
}

class _SpaceTabState extends ConsumerState<SpaceTab> {
  final _scroll = SmoothScrollController();
  late final AdminPoller _poller;

  /// Righe mostrate per sezione (id → quante); assente vale [_pageSize].
  final _shown = <String, int>{};

  /// Le serie aperte (`seriesKey`); all'inizio sono tutte chiuse.
  final _open = <String>{};

  @override
  void initState() {
    super.initState();
    _poller = AdminPoller(
      read: () => ref.read(spaceControllerProvider.notifier).reload(),
      interval: const Duration(seconds: 60),
    )..start();
  }

  @override
  void dispose() {
    _poller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() => ref.read(spaceControllerProvider.notifier).reload();

  /// Un'azione del controller: un errore diventa un avviso.
  Future<void> _run(Future<SpaceFailure?> Function() action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failure = await action();
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(spaceFailureLabel(l, failure))),
      );
    }
  }

  Future<void> _lighten(String key, String title) async {
    await showDownloadSearch(context, key, title, lighten: true);
    if (mounted) await _reload();
  }

  Future<void> _start(
    String kind,
    String key,
    String title, {
    int? sizeBytes,
  }) => startSpaceOperation(
    context,
    ref,
    kind: kind,
    key: key,
    title: title,
    sizeBytes: sizeBytes,
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.circleAlert, size: 14, color: WfColors.gold),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(color: WfColors.gold, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  /// Le prime righe di [items], poi "Mostra altri" (decisione 1).
  List<Widget> _page<T>(
    String id,
    List<T> items,
    Widget Function(T item) build,
  ) {
    final shown = _shown[id] ?? _pageSize;
    return [
      for (final item in items.take(shown)) build(item),
      if (items.length > shown)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => setState(() => _shown[id] = shown + _pageSize),
            child: Text(AppLocalizations.of(context).spaceShowMore),
          ),
        ),
    ];
  }

  /// Le stagioni con la stessa serie (almeno due) in un solo elemento, al
  /// posto della prima.
  List<Object> _entries(List<SpaceCandidate> delete) {
    final bySeries = <String, List<SpaceCandidate>>{};
    for (final c in delete) {
      final series = c.seriesKey;
      if (c.seasonNumber != null && series != null) {
        (bySeries[series] ??= []).add(c);
      }
    }
    final done = <String>{};
    final entries = <Object>[];
    for (final c in delete) {
      final group = bySeries[c.seriesKey];
      if (group == null || group.length < 2) {
        entries.add(c);
      } else if (done.add(c.seriesKey!)) {
        entries.add(group);
      }
    }
    return entries;
  }

  Widget _candidate(
    SpaceOverview o,
    SpaceCandidate c,
    DateTime now, {
    bool seasonOnly = false,
  }) => SpaceCandidateRow(
    key: ValueKey('delete-${c.key}'),
    candidate: c,
    topGenres: o.topGenres,
    now: now,
    showSeasonOnly: seasonOnly,
    onOpen: () => unawaited(
      showSpaceTitle(
        context,
        c,
        favoriteGenre: c.genres.any(o.topGenres.contains),
        canLighten: o.lighten.any((i) => i.key == c.key),
      ),
    ),
  );

  Widget _entry(SpaceOverview o, Object entry, DateTime now) {
    if (entry is SpaceCandidate) return _candidate(o, entry, now);
    final group = entry as List<SpaceCandidate>;
    final series = group.first.seriesKey!;
    return SpaceSeriesGroup(
      key: ValueKey('series-$series'),
      title: group.first.title,
      posterUrl: group.first.posterUrl,
      sizeBytes: group.fold(0, (sum, c) => sum + c.sizeBytes),
      expanded: _open.contains(series),
      onToggle: () => setState(
        () => _open.contains(series) ? _open.remove(series) : _open.add(series),
      ),
      children: [
        for (final c in group) _candidate(o, c, now, seasonOnly: true),
      ],
    );
  }

  Widget _quotaCard(AppLocalizations l, SpaceOverview o, DateTime now) {
    final quota = o.quota;
    final b = o.breakdown;
    final scannedAt = o.scannedAt;
    final status = scannedAt != null
        ? l.spaceCalculated(adminTimeLabel(scannedAt, now, l))
        : o.scanning
        ? l.spaceCalculating
        : l.spaceScanFailed;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    return AdminCard(
      title: l.adminTabSpace,
      icon: LucideIcons.hardDrive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quota != null && quota.limitBytes > 0) ...[
            Text(
              l.spaceQuotaLine(
                spaceTb(l, quota.usedBytes),
                spaceTb(l, quota.limitBytes),
                spaceTb(l, quota.limitBytes - quota.usedBytes),
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (quota.usedBytes / quota.limitBytes).clamp(0.0, 1.0),
                minHeight: 8,
                color: WfColors.gold,
                backgroundColor: WfColors.border,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (scannedAt != null)
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                for (final (label, bytes) in [
                  (l.spaceBreakdownMovies, b.moviesBytes),
                  (l.spaceBreakdownSeries, b.seriesBytes),
                  (l.spaceBreakdownAnime, b.animeBytes),
                  (l.spaceBreakdownTorrentOnly, b.torrentOnlyBytes),
                  (l.spaceBreakdownOther, b.otherBytes),
                ])
                  Text(
                    l.spaceBreakdownItem(label, spaceGb(l, bytes)),
                    style: muted,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(status, style: muted),
              AdminActionButton(
                label: l.spaceRecalculate,
                icon: LucideIcons.refreshCw,
                onPressed: o.scanning
                    ? null
                    : () => _run(
                        ref.read(spaceControllerProvider.notifier).recalculate,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _group(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        color: WfColors.creamMuted,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  List<Widget> _cleanup(AppLocalizations l, SpaceOverview o) {
    final c = o.cleanup;
    final removable = [
      for (final t in c.torrents)
        if (t.canRemoveNow) t,
    ];
    final removableBytes = removable.fold(0, (sum, t) => sum + t.sizeBytes);
    final files = [
      for (final f in c.orphans) (f, 'Orphan'),
      for (final f in c.duplicates) (f, 'Duplicate'),
    ];
    if (c.torrents.isEmpty && files.isEmpty) {
      return [AdminEmptyText(text: l.spaceEmptyCleanup)];
    }
    return [
      if (removable.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AdminActionButton(
            label: l.spaceRemoveAll(
              removable.length,
              spaceGb(l, removableBytes),
            ),
            icon: LucideIcons.trash2,
            onPressed: () => _start(
              'AllTorrents',
              'all-torrents',
              l.spaceRemoveAllTitle,
              sizeBytes: removableBytes,
            ),
          ),
        ),
      if (c.torrents.isNotEmpty) ...[
        _group(l.spaceGroupTorrents),
        ..._page(
          'torrents',
          c.torrents,
          (t) => SpaceTorrentRow(
            key: ValueKey('torrent-${t.key}'),
            torrent: t,
            onRemove: () =>
                _start('Torrent', t.key, t.name, sizeBytes: t.sizeBytes),
          ),
        ),
      ],
      if (files.isNotEmpty) ...[
        _group(l.spaceGroupFiles),
        ..._page(
          'files',
          files,
          (e) => SpaceFileRow(
            key: ValueKey('file-${e.$1.key}'),
            file: e.$1,
            onDelete: () =>
                _start(e.$2, e.$1.key, e.$1.path, sizeBytes: e.$1.sizeBytes),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(spaceControllerProvider);
    final o = data.value;
    if (o == null) {
      final error = data.error;
      return adminTabState(
        context,
        widget.header,
        error == null
            ? const LoadingView()
            : Center(
                child: AdminCardError(
                  error: error,
                  onRetry: () => unawaited(_reload()),
                ),
              ),
      );
    }
    // Decisione 9: 5 s mentre il plugin calcola, poi 60 s.
    _poller.interval = Duration(seconds: o.scanning ? 5 : 60);
    final now = clock.now();
    final e = o.errors;
    final notes = [
      for (final (service, code) in [
        ('radarr', e.radarr),
        ('sonarr', e.sonarr),
        ('qbit', e.qbit),
        ('seerr', e.seerr),
        ('quota', e.quota),
      ])
        ?spaceServiceError(l, service, code),
    ];
    final ready = o.scannedAt != null;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        adminSideMargin(context),
        0,
        adminSideMargin(context),
        40,
      ),
      children: [
        if (widget.header case final header?)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: header),
        for (final text in notes) _note(text),
        const SizedBox(height: 12),
        _quotaCard(l, o, now),
        if (ready) ...[
          AdminSectionTitle(title: l.spaceSectionDelete),
          if (o.delete.isEmpty) AdminEmptyText(text: l.spaceEmptyDelete),
          ..._page('delete', _entries(o.delete), (x) => _entry(o, x, now)),
          AdminSectionTitle(title: l.spaceSectionLighten),
          if (o.lighten.isEmpty) AdminEmptyText(text: l.spaceEmptyLighten),
          ..._page(
            'lighten',
            o.lighten,
            (i) => SpaceLightenRow(
              key: ValueKey('lighten-${i.key}'),
              item: i,
              onLighten: () =>
                  _lighten(i.key, spaceTitleOf(l, i.title, i.seasonNumber)),
            ),
          ),
          AdminSectionTitle(title: l.spaceSectionCleanup),
          ..._cleanup(l, o),
          AdminSectionTitle(title: l.spaceSectionPending),
          if (o.pending.isEmpty) AdminEmptyText(text: l.spaceEmptyPending),
          ..._page(
            'pending',
            o.pending,
            (p) => SpacePendingRow(
              key: ValueKey('pending-${p.hash}'),
              pending: p,
              onDrop: () => _run(
                () => ref
                    .read(spaceControllerProvider.notifier)
                    .dropPending(p.hash),
              ),
            ),
          ),
          AdminSectionTitle(title: l.spaceSectionKept),
          if (o.kept.isEmpty) AdminEmptyText(text: l.spaceEmptyKept),
          ..._page(
            'kept',
            o.kept,
            (k) => SpaceKeptRow(
              key: ValueKey('kept-${k.key}'),
              kept: k,
              onUnkeep: () => _run(
                () => ref.read(spaceControllerProvider.notifier).unkeep(k.key),
              ),
            ),
          ),
          AdminSectionTitle(title: l.spaceSectionOperations),
          if (o.operations.isEmpty)
            AdminEmptyText(text: l.spaceEmptyOperations),
          ..._page(
            'operations',
            o.operations,
            (op) => SpaceOperationRow(
              key: ValueKey('op-${op.id}'),
              operation: op,
              now: now,
            ),
          ),
        ],
      ],
    );
  }
}
