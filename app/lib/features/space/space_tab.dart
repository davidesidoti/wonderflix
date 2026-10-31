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
import 'space_bulk.dart';
import 'space_controller.dart';
import 'space_labels.dart';
import 'space_operation_dialog.dart';
import 'space_providers.dart';
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

  /// In selezione: le righe di "Cancellare" hanno la casella (decisione 1).
  var _selecting = false;

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

  /// Import a mano di un download bloccato; poi rilegge, così la riga passa a
  /// "In importazione".
  Future<void> _import(String key) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(spaceApiProvider).importLighten(key);
    } on SpaceException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(spaceImportFailureLabel(l, e))),
      );
      return;
    }
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
      // Una riga Series è sempre una riga a sé, anche con la stessa chiave.
      if (c.seasonNumber != null && series != null) {
        (bySeries[series] ??= []).add(c);
      }
    }
    final done = <String>{};
    final entries = <Object>[];
    for (final c in delete) {
      final group = c.seasonNumber == null ? null : bySeries[c.seriesKey];
      if (group == null || group.length < 2) {
        entries.add(c);
      } else if (done.add(c.seriesKey!)) {
        entries.add(group);
      }
    }
    return entries;
  }

  void _toggle(Iterable<String> keys) =>
      ref.read(spaceSelectionProvider.notifier).toggle(keys);

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
    selected: _selecting
        ? ref.watch(spaceSelectionProvider).contains(c.key)
        : null,
    onOpen: _selecting
        ? () => _toggle([c.key])
        : () => unawaited(
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
    final keys = [for (final c in group) c.key];
    final chosen = keys.where(ref.watch(spaceSelectionProvider).contains);
    return SpaceSeriesGroup(
      onSelect: _selecting ? () => _toggle(keys) : null,
      selected: chosen.isEmpty
          ? false
          : chosen.length == keys.length
          ? true
          : null,
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

  /// "Tieni selezionati" in corso: spegne anche "Elimina selezionati".
  bool _keepingBulk = false;

  Future<void> _keepSelected(
    AppLocalizations l,
    List<SpaceCandidate> counted,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _keepingBulk = true);
    final List<SpaceFailure> failures;
    try {
      failures = await ref.read(spaceControllerProvider.notifier).keepAll([
        for (final c in counted)
          (c.key, spaceTitleOf(l, c.title, c.seasonNumber)),
      ]);
    } finally {
      if (mounted) setState(() => _keepingBulk = false);
    }
    if (!mounted) return;
    ref.read(spaceSelectionProvider.notifier).clear();
    setState(() => _selecting = false);
    final ok = counted.length - failures.length;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failures.isEmpty
              ? l.spaceKeptCount(ok)
              : l.spaceKeepPartial(
                  ok,
                  failures.length,
                  spaceFailureLabel(l, failures.first),
                ),
        ),
      ),
    );
  }

  /// La barra in fondo alla selezione, ferma mentre la lista scorre.
  Widget _selectionBar(AppLocalizations l, SpaceOverview o) {
    final keys = ref.watch(spaceSelectionProvider);
    final chosen = [
      for (final c in o.delete)
        if (keys.contains(c.key)) c,
    ];
    final counted = dedupeSpaceSelection(chosen);
    return Material(
      color: WfColors.surface,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: adminSideMargin(context),
          vertical: 8,
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () {
                ref.read(spaceSelectionProvider.notifier).clear();
                setState(() => _selecting = false);
              },
              child: Text(l.spaceCancelSelection),
            ),
            AdminActionButton(
              label: l.spaceKeepSelected(counted.length),
              icon: LucideIcons.shield,
              onPressed: chosen.isEmpty || _keepingBulk
                  ? null
                  : () => _keepSelected(l, counted),
            ),
            AdminActionButton(
              label: l.spaceDeleteSelected(
                counted.length,
                spaceGb(l, counted.fold(0, (s, c) => s + c.freeNowBytes)),
              ),
              icon: LucideIcons.trash2,
              onPressed: chosen.isEmpty || _keepingBulk
                  ? null
                  : () async {
                      await startSpaceBulk(context, ref, chosen);
                      if (mounted && ref.read(spaceSelectionProvider).isEmpty) {
                        setState(() => _selecting = false);
                      }
                    },
            ),
          ],
        ),
      ),
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

  Widget _totals(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: WfColors.creamMuted, fontSize: 13),
    ),
  );

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

  List<Widget> _torrentGroup(
    String id,
    String title,
    List<SpaceTorrent> list,
  ) => list.isEmpty
      ? const []
      : [
          _group(title),
          ..._page(
            id,
            list,
            (t) => SpaceTorrentRow(
              key: ValueKey('torrent-${t.key}'),
              torrent: t,
              onRemove: () =>
                  _start('Torrent', t.key, t.name, sizeBytes: t.sizeBytes),
            ),
          ),
        ];

  List<Widget> _fileGroup(
    String id,
    String title,
    String kind,
    List<SpaceFile> list,
  ) => list.isEmpty
      ? const []
      : [
          _group(title),
          ..._page(
            id,
            list,
            (f) => SpaceFileRow(
              key: ValueKey('file-${f.key}'),
              file: f,
              onDelete: () =>
                  _start(kind, f.key, f.path, sizeBytes: f.sizeBytes),
            ),
          ),
        ];

  List<Widget> _cleanup(AppLocalizations l, SpaceOverview o) {
    final c = o.cleanup;
    final removable = [
      for (final t in c.torrents)
        if (t.canRemoveNow) t,
    ];
    final removableBytes = removable.fold(0, (sum, t) => sum + t.sizeBytes);
    if (c.isEmpty) {
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
      ..._torrentGroup('now', l.spaceGroupRemovableNow, removable),
      ..._torrentGroup('seed', l.spaceGroupSeedRule, [
        for (final t in c.torrents)
          if (!t.canRemoveNow) t,
      ]),
      ..._fileGroup('orphans', l.spaceGroupOrphans, 'Orphan', c.orphans),
      ..._fileGroup(
        'duplicates',
        l.spaceGroupDuplicates,
        'Duplicate',
        c.duplicates,
      ),
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
    // Decisione 9: 5 s mentre il plugin calcola o una riga scarica, poi 60 s.
    // Un download bloccato aspetta l'admin, non il plugin.
    final downloading = o.lighten.any(
      (i) => !const {null, 'Failed', 'Blocked'}.contains(i.download?.state),
    );
    _poller.interval = Duration(seconds: o.scanning || downloading ? 5 : 60);
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
    final list = ListView(
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
          if (o.delete.isNotEmpty)
            _totals(
              l.spaceTotalsDelete(
                spaceGb(l, o.delete.fold(0, (s, c) => s + c.freeNowBytes)),
                spaceGb(l, o.delete.fold(0, (s, c) => s + c.freeLaterBytes)),
              ),
            ),
          if (o.delete.isEmpty) AdminEmptyText(text: l.spaceEmptyDelete),
          if (o.delete.isNotEmpty && !_selecting)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _selecting = true),
                icon: const Icon(LucideIcons.squareCheck, size: 16),
                label: Text(l.spaceSelect),
              ),
            ),
          ..._page('delete', _entries(o.delete), (x) => _entry(o, x, now)),
          AdminSectionTitle(title: l.spaceSectionLighten),
          if (o.lighten.isEmpty) AdminEmptyText(text: l.spaceEmptyLighten),
          ..._page(
            'lighten',
            o.lighten,
            (i) => SpaceLightenRow(
              key: ValueKey('lighten-${i.key}'),
              item: i,
              onOpen: () => unawaited(showSpaceLighten(context, i)),
              onLighten: () =>
                  _lighten(i.key, spaceTitleOf(l, i.title, i.seasonNumber)),
              onImport: () => _import(i.key),
            ),
          ),
          AdminSectionTitle(title: l.spaceSectionCleanup),
          if (!o.cleanup.isEmpty)
            _totals(
              l.spaceTotalsCleanup(
                spaceGb(
                  l,
                  [
                    for (final t in o.cleanup.torrents)
                      if (t.canRemoveNow) t.sizeBytes,
                    for (final f in [
                      ...o.cleanup.orphans,
                      ...o.cleanup.duplicates,
                    ])
                      if (!f.linked) f.sizeBytes,
                  ].fold(0, (s, b) => s + b),
                ),
              ),
            ),
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
              onOpen: () => unawaited(showSpaceOperation(context, op.id)),
            ),
          ),
        ],
      ],
    );
    if (!_selecting || !ready) return list;
    if (o.delete.isEmpty) {
      // Niente da scegliere: niente barra, e si esce dalla selezione.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selecting = false);
      });
      return list;
    }
    return Column(
      children: [
        Expanded(child: list),
        _selectionBar(l, o),
      ],
    );
  }
}
