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
import '../admin/admin_poller.dart';
import '../admin/admin_time.dart';
import '../admin/admin_widgets.dart';
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

  final _scroll = SmoothScrollController();
  late final AdminPoller _poller;
  bool _allRecent = false;
  int _reviewShown = _reviewPage;

  /// Le sezioni chiuse, per id; restano tra una visita e l'altra.
  static const _collapsedKey = 'downloads.collapsedSections';
  Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    try {
      _collapsed = ref
              .read(sharedPreferencesProvider)
              .getStringList(_collapsedKey)
              ?.toSet() ??
          {};
    } on TypeError {
      // Valore di un altro tipo sotto la chiave: tutte aperte.
    }
    // Decisione 4: si rilegge ogni minuto finché la scheda è aperta.
    _poller = AdminPoller(
      read: () => ref.read(downloadsControllerProvider.notifier).reload(),
      interval: const Duration(seconds: 60),
    )..start();
  }

  @override
  void dispose() {
    _poller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(String id) {
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

  Widget _header(String id, String title) => _SectionHeader(
    title: title,
    expanded: !_collapsed.contains(id),
    onToggle: () => _toggle(id),
  );

  Future<void> _reload() =>
      ref.read(downloadsControllerProvider.notifier).reload();

  /// Apre la ricerca; chiusa la pagina rilegge (un grab finito dopo la
  /// chiusura lascerebbe la panoramica vecchia fino al giro dopo).
  Future<void> _open(String key, String title, {bool reviewing = false}) async {
    await showDownloadSearch(context, key, title, reviewing: reviewing);
    if (mounted) await _reload();
  }

  Future<void> _searchNow(String key) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(downloadsApiProvider).searchNow(key);
    } on DownloadsException catch (e) {
      // Un errore del plugin è atteso: si mostra, non è un difetto da loggare.
      messenger.showSnackBar(
        SnackBar(content: Text(downloadsFailureLabel(l, e.failure))),
      );
    }
    if (!mounted) return;
    await _reload();
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
    final needsYou = [
      for (final i in overview.waiting)
        if (i.state == DownloadState.needsYou) i,
    ];
    final waiting = [
      for (final i in overview.waiting)
        if (i.state != DownloadState.needsYou) i,
    ];
    final recent = _allRecent
        ? overview.recent
        : [
            for (final c in overview.recent)
              if (now.difference(c.at) <= _recentWindow) c,
          ];
    final review = overview.review;
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
        if (!overview.enabled)
          _Note(text: l.downloadsDisabledNote, icon: LucideIcons.info),
        for (final text in errors)
          _Note(text: text, icon: LucideIcons.circleAlert),
        if (needsYou.isNotEmpty) ...[
          _header(
            'needsYou',
            '${l.downloadsSectionNeedsYou} · ${needsYou.length}',
          ),
          if (!_collapsed.contains('needsYou'))
            for (final item in needsYou) _itemRow(item, now),
        ],
        _header('chosen', '${l.downloadsSectionChosen} · ${recent.length}'),
        if (!_collapsed.contains('chosen')) ...[
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
          if (!_allRecent && recent.length < overview.recent.length)
            _MoreButton(onPressed: () => setState(() => _allRecent = true)),
        ],
        _header('waiting', '${l.downloadsSectionWaiting} · ${waiting.length}'),
        if (!_collapsed.contains('waiting')) ...[
          if (waiting.isEmpty) AdminEmptyText(text: l.downloadsNothingYet),
          for (final item in waiting) _itemRow(item, now),
        ],
        _header('review', '${l.downloadsSectionReview} · ${review.length}'),
        if (!_collapsed.contains('review')) ...[
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
          for (final item in review.take(_reviewShown))
            ReviewRow(
              key: ValueKey('review-${item.key}'),
              item: item,
              onOpen: () =>
                  unawaited(_open(item.key, item.title, reviewing: true)),
            ),
          if (review.length > _reviewShown)
            _MoreButton(
              onPressed: () => setState(() => _reviewShown += _reviewPage),
            ),
        ],
      ],
    );
  }

  Widget _itemRow(DownloadItem item, DateTime now) => DownloadItemRow(
    key: ValueKey('item-${item.key}'),
    item: item,
    now: now,
    onWatch: () => unawaited(_open(item.key, item.title)),
    onSearchNow: () => _searchNow(item.key),
  );
}

/// Il titolo di una sezione, tutta la riga si tocca per chiuderla o aprirla
/// (spec T §8.1). Stesso aspetto di [AdminSectionTitle].
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
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
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
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
