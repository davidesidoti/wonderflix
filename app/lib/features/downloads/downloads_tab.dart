import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../../l10n/gen/app_localizations.dart';
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

  @override
  void initState() {
    super.initState();
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
          SnackBar(content: Text(downloadsFailureLabel(l, e.failure))));
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
          adminSideMargin(context), 0, adminSideMargin(context), 40),
      children: [
        if (widget.header case final header?)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: header),
        if (!overview.enabled)
          _Note(text: l.downloadsDisabledNote, icon: LucideIcons.info),
        for (final text in errors)
          _Note(text: text, icon: LucideIcons.circleAlert),
        if (needsYou.isNotEmpty) ...[
          AdminSectionTitle(
              title: '${l.downloadsSectionNeedsYou} · ${needsYou.length}'),
          for (final item in needsYou) _itemRow(item, now),
        ],
        AdminSectionTitle(
            title: '${l.downloadsSectionChosen} · ${recent.length}'),
        if (recent.isEmpty) AdminEmptyText(text: l.downloadsNothingYet),
        for (final choice in recent)
          DownloadChoiceRow(
            key: ValueKey('choice-${choice.key}-${choice.at.toIso8601String()}'),
            choice: choice,
            now: now,
            onChange: () => unawaited(_open(choice.key, choice.title)),
          ),
        if (!_allRecent && recent.length < overview.recent.length)
          _MoreButton(onPressed: () => setState(() => _allRecent = true)),
        AdminSectionTitle(
            title: '${l.downloadsSectionWaiting} · ${waiting.length}'),
        if (waiting.isEmpty) AdminEmptyText(text: l.downloadsNothingYet),
        for (final item in waiting) _itemRow(item, now),
        AdminSectionTitle(
            title: '${l.downloadsSectionReview} · ${review.length}'),
        if (reviewAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l.downloadsReviewAt(adminTimeLabel(reviewAt, now, l)),
                style: const TextStyle(
                    color: WfColors.creamMuted, fontSize: 13)),
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
              onPressed: () => setState(() => _reviewShown += _reviewPage)),
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
              child: Text(text,
                  style: const TextStyle(color: WfColors.gold, fontSize: 13)),
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
