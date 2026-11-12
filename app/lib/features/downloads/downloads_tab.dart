import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/tv_focusable.dart';
import '../admin/admin_action_button.dart';
import '../admin/admin_confirm_dialog.dart';
import '../admin/admin_kit.dart';
import '../admin/admin_poller.dart';
import '../admin/admin_time.dart';
import '../admin/admin_widgets.dart';
import 'download_filter.dart';
import 'download_labels.dart';
import 'download_rows.dart';
import 'download_search_page.dart';
import 'downloads_controller.dart';
import 'downloads_providers.dart';

final _log = Logger('downloads');

/// La scheda Download (spec T §8.1): panoramica dei download automatici in
/// quattro sezioni.
class DownloadsTab extends ConsumerStatefulWidget {
  const DownloadsTab({super.key, this.header});

  /// La striscia del server, nel layout stretto: scorre con l'elenco.
  final Widget? header;

  @override
  ConsumerState<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends ConsumerState<DownloadsTab> {
  /// Le scelte si vedono per 7 giorni, poi tutte (decisione 3 del piano 29b).
  static const _recentWindow = Duration(days: 7);
  static const _reviewPage = 50;
  static const _slowPoll = Duration(seconds: 60);
  static const _fastPoll = Duration(seconds: 5);

  final _scroll = SmoothScrollController();
  late final AdminPoller _poller;
  bool _allRecent = false;
  int _reviewShown = _reviewPage;

  /// Le sezioni chiuse, per id; restano tra una visita e l'altra.
  static const _collapsedKey = 'downloads.collapsedSections';
  Set<String> _collapsed = {};

  /// Il campo "Cerca nella lista"; non si salva tra una visita e l'altra.
  final _filter = TextEditingController();

  /// Il campo sulla TV: prende il focus solo con OK (vedi [_filterField]).
  final _filterFocus = FocusNode(debugLabel: 'downloads-filter');

  /// Sulla TV: OK ha attivato il campo (fino a che perde il focus).
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _filterFocus.addListener(() {
      if (!_filterFocus.hasFocus && _typing) setState(() => _typing = false);
    });
    try {
      _collapsed = ref
              .read(sharedPreferencesProvider)
              .getStringList(_collapsedKey)
              ?.toSet() ??
          {};
    } on TypeError {
      // Valore di un altro tipo sotto la chiave: tutte aperte.
    }
    // Decisione 4: si rilegge ogni minuto finché la scheda è aperta; ogni 5
    // secondi se una voce è in coda per la ricerca o ci sta cercando, o se
    // "Aggiorna ora" aspetta il giro.
    _poller = AdminPoller(
      read: () => ref.read(downloadsControllerProvider.notifier).reload(),
      interval: _slowPoll,
    )..start();
    ref.listenManual(downloadsControllerProvider, (_, next) {
      final overview = next.value;
      if (overview == null) return;
      _poller.interval =
          overview.waiting.any((i) => i.searchPhase != null) ||
              overview.refreshPending == true
          ? _fastPoll
          : _slowPoll;
    });
  }

  @override
  void dispose() {
    _poller.dispose();
    _scroll.dispose();
    _filter.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    // Con il filtro le sezioni sono tutte aperte: un tocco non cambia niente.
    if (_filter.text.trim().isNotEmpty) return;
    setState(
      () =>
          _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id),
    );
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setStringList(_collapsedKey, _collapsed.toList());
    } on Object catch (error) {
      // La scelta vale fino alla chiusura della scheda.
      _log.warning('sezioni chiuse non salvate: ${error.runtimeType}');
    }
  }

  Widget _header(String id, String title, int count) => _SectionHeader(
    title: title,
    count: count,
    expanded: _isOpen(id),
    onToggle: () => _toggle(id),
  );

  /// Con il filtro le sezioni sono tutte aperte, senza toccare quelle salvate.
  bool _isOpen(String id) =>
      _filter.text.trim().isNotEmpty || !_collapsed.contains(id);

  /// Il campo. Sulla TV il focus iniziale aprirebbe subito la tastiera: la
  /// cornice (`TvFocusable`) è l'unica tappa del telecomando e OK lo attiva,
  /// come nella ricerca.
  Widget _filterField(AppLocalizations l) {
    final tv = FormFactor.of(context).tv;
    final field = TextField(
      key: const ValueKey('downloads-filter'),
      controller: _filter,
      focusNode: tv ? _filterFocus : null,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: l.downloadsFilterHint,
        prefixIcon: const Icon(LucideIcons.search, color: WfColors.creamMuted),
        suffixIcon: _filter.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.x, color: WfColors.creamMuted),
                onPressed: () => setState(_filter.clear),
              ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: !tv
          ? field
          : TvFocusable(
              onActivate: () {
                setState(() => _typing = true);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _filterFocus.requestFocus(),
                );
              },
              child: ExcludeFocus(excluding: !_typing, child: field),
            ),
    );
  }

  Future<void> _reload() =>
      ref.read(downloadsControllerProvider.notifier).reload();

  /// Apre la ricerca; chiusa la pagina rilegge (un grab finito dopo la
  /// chiusura lascerebbe la panoramica vecchia fino al giro dopo).
  Future<void> _open(String key, String title, {bool reviewing = false}) async {
    await showDownloadSearch(context, key, title, reviewing: reviewing);
    if (mounted) await _reload();
  }

  /// Un pulsante di una riga (spec "Serve te" §6): chiama il plugin, dice
  /// l'esito e rilegge. "Scegli tu" apre la ricerca.
  Future<void> _act(DownloadAction action, DownloadItem item) async {
    final key = item.key;
    if (action == DownloadAction.pick) {
      unawaited(_open(key, item.title));
      return;
    }
    if (action == DownloadAction.externalSearch) {
      if (item.externalSearchUrl case final url?) {
        await openExternalSearch(context, url);
      }
      return;
    }
    final api = ref.read(downloadsApiProvider);
    await _call(switch (action) {
      DownloadAction.grabBest => () => api.grabBest(key),
      DownloadAction.snooze => () => api.snooze(key),
      DownloadAction.import => () => api.importBlocked(key),
      DownloadAction.discard => () => api.discard(key),
      DownloadAction.searchNow ||
      DownloadAction.pick ||
      DownloadAction.externalSearch => () => api.searchNow(key),
    }, started: action == DownloadAction.searchNow);
  }

  /// Chiama il plugin, dice l'esito ("Ricerca avviata" se [started]) e
  /// rilegge.
  Future<void> _call(
    Future<void> Function() request, {
    bool started = false,
  }) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await request();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            started ? l.downloadsSearchStarted : l.downloadsActionDone,
          ),
        ),
      );
    } on DownloadsException catch (e) {
      // Un errore del plugin è atteso: si mostra, non è un difetto da loggare.
      messenger.showSnackBar(
        SnackBar(content: Text(downloadsFailureLabel(l, e.failure))),
      );
    }
    if (!mounted) return;
    await _reload();
  }

  /// "Rimuovi" cancella torrent e file per sempre: prima si chiede.
  Future<void> _removeUnknown(UnknownDownload item) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.downloadsUnknownConfirmTitle,
      message: l.downloadsUnknownConfirmMessage(
        item.title,
        formatGb(l, item.sizeBytes),
      ),
      confirmLabel: l.downloadsUnknownRemove,
    );
    if (!confirmed || !mounted) return;
    await _call(
      () => ref
          .read(downloadsApiProvider)
          .removeUnknown(item.service, item.downloadId),
    );
  }

  /// Il testo di un errore di Sonarr o Radarr, con le etichette di Home e
  /// calendario.
  String _arrError(AppLocalizations l, String service, String code) {
    final detail = switch (code) {
      'NotConfigured' => l.adminArrNotConfigured,
      'Unauthorized' => l.adminArrUnauthorized,
      _ => l.adminArrUnreachable,
    };
    return l.downloadsArrError(service, detail);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(downloadsControllerProvider);
    final overview = data.value;
    if (overview == null) {
      final error = data.error;
      if (error == null) {
        return adminTabState(context, widget.header, const LoadingView());
      }
      return adminTabState(
        context,
        widget.header,
        Center(
          child: AdminCardError(
            error: error,
            onRetry: () => unawaited(_reload()),
          ),
        ),
      );
    }
    final now = clock.now();
    final q = _filter.text.trim();
    final filtering = q.isNotEmpty;
    bool shown(String title) => !filtering || titleMatches(title, q);
    final needsYou = [
      for (final i in overview.waiting)
        if (i.state == DownloadState.needsYou && shown(i.title)) i,
    ];
    final waiting = [
      for (var rank = 0; rank <= 3; rank++)
        for (final i in overview.waiting)
          if (i.state != DownloadState.needsYou &&
              _waitingRank(i) == rank &&
              shown(i.title))
            i,
    ];
    // Con il filtro valgono tutte le scelte, anche quelle oltre i 7 giorni.
    final recent = filtering
        ? [
            for (final c in overview.recent)
              if (shown(c.title)) c,
          ]
        : _allRecent
        ? overview.recent
        : [
            for (final c in overview.recent)
              if (now.difference(c.at) <= _recentWindow) c,
          ];
    final unknown = [
      for (final u in overview.unknown)
        if (shown(u.title)) u,
    ];
    final review = [
      for (final r in overview.review)
        if (shown(r.title)) r,
    ];
    final rushGroupsShown = filtering
        ? rushGroups(overview.waiting, q)
        : const <DownloadRushGroup>[];
    // Il titolo non è tra le righe in attesa: forse è appena stato aggiunto.
    final notListed =
        filtering &&
        overview.enabled &&
        overview.refreshPending != null &&
        !overview.waiting.any((i) => titleMatches(i.title, q));
    final reviewAt = overview.reviewAt;
    final errors = [
      if (overview.sonarrError case final code?) _arrError(l, 'Sonarr', code),
      if (overview.radarrError case final code?) _arrError(l, 'Radarr', code),
    ];
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
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AdminTabTitle(title: l.adminTabDownloads),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AdminActionButton(
              label: l.adminActivityRefresh,
              icon: LucideIcons.rotateCw,
              onPressed: _reload,
            ),
          ),
        ),
        _filterField(l),
        for (final group in rushGroupsShown)
          DownloadRushRow(
            key: ValueKey('rush-${group.key}'),
            group: group,
            enabled: overview.enabled,
            onRush: overview.enabled && group.canPress
                ? () => _call(
                    () => ref.read(downloadsApiProvider).rush(group.key),
                    started: true,
                  )
                : null,
          ),
        if (notListed)
          _NotListed(
            refreshing: overview.refreshPending == true,
            onRefresh: () => _call(ref.read(downloadsApiProvider).refresh),
          ),
        if (overview.progress case final progress?)
          _BacklogCard(
            progress: progress,
            now: now,
            broken: overview.sonarrError != null || overview.radarrError != null,
          ),
        if (!overview.enabled)
          _Note(text: l.downloadsDisabledNote, icon: LucideIcons.info),
        for (final text in errors)
          _Note(text: text, icon: LucideIcons.circleAlert),
        if (needsYou.isNotEmpty) ...[
          _header(
            'needsYou',
            l.downloadsSectionNeedsYou,
            needsYou.length,
          ),
          if (_isOpen('needsYou'))
            for (final item in needsYou) _itemRow(item, now),
        ],
        if (unknown.isNotEmpty) ...[
          _header(
            'unknown',
            l.downloadsSectionUnknown,
            unknown.length,
          ),
          if (_isOpen('unknown'))
            for (final item in unknown)
              UnknownDownloadRow(
                key: ValueKey('unknown-${item.service}-${item.downloadId}'),
                item: item,
                onRemove: () => _removeUnknown(item),
              ),
        ],
        if (!filtering || recent.isNotEmpty)
          _header('chosen', l.downloadsSectionChosen, recent.length),
        if ((!filtering || recent.isNotEmpty) && _isOpen('chosen')) ...[
          if (recent.isEmpty) AdminEmptyText(text: l.downloadsNothingYet),
          for (final choice in recent)
            DownloadChoiceRow(
              key: ValueKey(
                'choice-${choice.key}-${choice.at.toIso8601String()}',
              ),
              choice: choice,
              now: now,
              onChange: () => unawaited(_open(choice.key, choice.title)),
            ),
          if (!filtering &&
              !_allRecent &&
              recent.length < overview.recent.length)
            _MoreButton(onPressed: () => setState(() => _allRecent = true)),
        ],
        if (!filtering || waiting.isNotEmpty)
          _header('waiting', l.downloadsSectionWaiting, waiting.length),
        if ((!filtering || waiting.isNotEmpty) && _isOpen('waiting')) ...[
          if (waiting.isEmpty) AdminEmptyText(text: l.downloadsNothingYet),
          for (final item in waiting) _itemRow(item, now),
        ],
        if (!filtering || review.isNotEmpty)
          _header('review', l.downloadsSectionReview, review.length),
        if ((!filtering || review.isNotEmpty) && _isOpen('review')) ...[
          if (reviewAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.downloadsReviewAt(adminTimeLabel(reviewAt, now, l)),
                style: const TextStyle(
                  color: WfColors.creamMuted,
                  fontSize: 13,
                ),
              ),
            ),
          if (review.isEmpty) AdminEmptyText(text: l.downloadsNothingYet),
          for (final item in filtering ? review : review.take(_reviewShown))
            ReviewRow(
              key: ValueKey('review-${item.key}'),
              item: item,
              // Spenti, il giro non cerca: niente pulsante.
              onHunt: item.canHunt && overview.enabled
                  ? () => _call(
                        () => ref.read(downloadsApiProvider).hunt(item.key),
                        started: true,
                      )
                  : null,
              onOpen: () =>
                  unawaited(_open(item.key, item.title, reviewing: true)),
            ),
          if (!filtering && review.length > _reviewShown)
            _MoreButton(
              onPressed: () => setState(() => _reviewShown += _reviewPage),
            ),
        ],
      ],
    );
  }

  /// "In attesa": prima ciò che è in corso; a pari grado resta l'ordine del
  /// plugin, così le righe non saltano tra un giro e l'altro.
  static int _waitingRank(DownloadItem item) {
    if (item.state == DownloadState.downloading) return 0;
    return switch (item.searchPhase) {
      DownloadSearchPhase.searching => 1,
      DownloadSearchPhase.queued => 2,
      null => 3,
    };
  }

  Widget _itemRow(DownloadItem item, DateTime now) => DownloadItemRow(
    key: ValueKey('item-${item.key}'),
    item: item,
    now: now,
    onAction: (action) => _act(action, item),
  );
}

/// Il titolo di una sezione, tutta la riga si tocca per chiuderla o aprirla
/// (spec T §8.1). Stesso aspetto di [AdminSectionTitle].
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: FormFactor.of(context).compact ? minTouchTarget : 0,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 18,
                  color: WfColors.creamMuted,
                ),
                const SizedBox(width: 8),
                Flexible(
                  // Un solo testo ("Titolo · 3"): il conteggio è la parte piccola.
                  child: Text.rich(
                    TextSpan(
                      text: title,
                      style: WfText.display(20),
                      children: [
                        TextSpan(
                          text: ' · $count',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: WfColors.creamMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// L'avanzamento della coda delle ricerche automatiche: "140 / 600", barra e
/// fine stimata. Stesso aspetto di [AdminCard]; su TV non prende il focus.
class _BacklogCard extends StatelessWidget {
  const _BacklogCard({
    required this.progress,
    required this.now,
    required this.broken,
  });

  final SearchProgress progress;
  final DateTime now;

  /// Sonarr o Radarr non rispondono: la spia è rossa.
  final bool broken;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final total = progress.total;
    final perHour = progress.perHour;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WfColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WfColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Senza baseline la spia andrebbe in cima: il fondo sta 4 px
              // sopra la linea del testo, cioè al centro delle cifre.
              Baseline(
                baseline: 12,
                baselineType: TextBaseline.alphabetic,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: WfLamp(
                    state: broken
                        ? LampState.broken
                        : progress.paused || progress.manualSearch
                            ? LampState.attention
                            : LampState.ok,
                    label: '${l.downloadsBacklogTitle}: ${broken ? l.downloadsBacklogBroken : progress.manualSearch ? l.downloadsBacklogManualSearch : progress.paused ? l.downloadsBacklogPaused : l.downloadsBacklogRunning}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${progress.done} / $total',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.downloadsBacklogTitle,
                  textAlign: TextAlign.end,
                  style: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RowProgressBar(value: total == 0 ? 0 : progress.done / total),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(backlogEndLabel(l, progress, now), style: muted),
              ),
              if (perHour != null) ...[
                const SizedBox(width: 12),
                Text(l.downloadsBacklogPerHour(perHour.round()), style: muted),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Una nota in cima: funzione spenta o servizio che non risponde.
class _Note extends StatelessWidget {
  const _Note({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: WfColors.gold),
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
}

/// "Non è in lista": il titolo cercato non ha righe; "Aggiorna ora" fa
/// rileggere Sonarr e Radarr.
class _NotListed extends StatelessWidget {
  const _NotListed({required this.refreshing, required this.onRefresh});

  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l.downloadsNotListed,
            style: const TextStyle(color: WfColors.creamMuted),
          ),
          if (refreshing)
            Text(
              l.downloadsRefreshing,
              style: const TextStyle(color: WfColors.creamMuted),
            )
          else
            AdminActionButton(
              label: l.downloadsRefreshNow,
              icon: LucideIcons.rotateCw,
              onPressed: onRefresh,
            ),
        ],
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      onPressed: onPressed,
      child: Text(AppLocalizations.of(context).downloadsShowMore),
    ),
  );
}
