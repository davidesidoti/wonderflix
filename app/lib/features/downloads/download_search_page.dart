import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../admin/admin_confirm_dialog.dart';
import '../admin/admin_widgets.dart';
import 'download_labels.dart';
import 'download_search_controller.dart';

/// La pagina a tutto schermo con le release di un titolo (spec T §8.2).
/// [reviewing]: aperta da "Da ripassare", con "Va bene così".
Future<void> showDownloadSearch(
  BuildContext context,
  String key,
  String title, {
  bool reviewing = false,
}) =>
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => Dialog.fullscreen(
        child: _SearchPage(dlKey: key, title: title, reviewing: reviewing),
      ),
    );

class _SearchPage extends ConsumerWidget {
  const _SearchPage({
    required this.dlKey,
    required this.title,
    required this.reviewing,
  });

  final String dlKey;
  final String title;
  final bool reviewing;

  /// Un errore dopo un'azione: la pagina resta, con il messaggio.
  void _fail(BuildContext context, DownloadsFailure failure) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(downloadsFailureLabel(
            AppLocalizations.of(context), failure)),
      ));

  Future<void> _grab(BuildContext context, WidgetRef ref,
      DownloadSearch search, DownloadCandidate c) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(downloadSearchControllerProvider(dlKey).notifier);
    // Decisione 5: conferma se non migliora il file attuale o non si importa.
    final current = search.current;
    final reasons = [
      if (current != null && c.release.score <= current.score)
        l.downloadsConfirmLowerScore(c.release.score, current.score),
      if (!c.wouldImport) l.downloadsConfirmNoImport,
    ];
    if (reasons.isNotEmpty) {
      final ok = await showAdminConfirmDialog(
        context,
        title: l.downloadsConfirmTitle,
        message: reasons.join('\n'),
        confirmLabel: l.downloadsGrab,
      );
      if (!ok || !context.mounted) return;
    }
    final failure = await controller.grab(c);
    if (!context.mounted) return;
    if (failure != null) return _fail(context, failure);
    messenger.showSnackBar(SnackBar(content: Text(l.downloadsStarted)));
    navigator.pop();
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final failure = await ref
        .read(downloadSearchControllerProvider(dlKey).notifier)
        .accept();
    if (!context.mounted) return;
    if (failure != null) return _fail(context, failure);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final provider = downloadSearchControllerProvider(dlKey);
    final state = ref.watch(provider);
    final busy = ref.watch(downloadGrabbingProvider(dlKey));
    final margin = adminSideMargin(context);
    final search = state.value;
    void again() => unawaited(ref.read(provider.notifier).searchAgain());

    Widget body;
    if (state.isLoading) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l.downloadsSearchWaiting,
              style: const TextStyle(color: WfColors.creamMuted)),
        ]),
      );
    } else if (search == null || search.error != null) {
      body = Center(
        child: Padding(
          padding: EdgeInsets.all(margin),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(_errorText(l, state.error, search?.error),
                  style: const TextStyle(color: WfColors.creamMuted)),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: again, child: Text(l.retry)),
          ]),
        ),
      );
    } else {
      body = ListView(
        padding: EdgeInsets.fromLTRB(margin, 8, margin, 40),
        children: [
          _Header(
            search: search,
            onAgain: again,
            onAccept: reviewing && !busy ? () => _accept(context, ref) : null,
            reviewing: reviewing,
          ),
          const SizedBox(height: 16),
          if (search.candidates.isEmpty) AdminEmptyText(text: l.downloadsNothingYet),
          if (search.candidates.isNotEmpty &&
              !FormFactor.of(context).compact)
            const _TableHead(),
          for (final c in search.candidates)
            _CandidateRow(
              key: ValueKey('candidate-${c.release.guid}'),
              candidate: c,
              onGrab: busy ? null : () => _grab(context, ref, search, c),
            ),
          if (search.rejected.isNotEmpty) ...[
            AdminSectionTitle(
                title: '${l.downloadsRejectedTitle} · ${search.rejected.length}'),
            for (final r in search.rejected) _RejectedRow(rejected: r),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: body,
    );
  }

  /// L'errore dell'eccezione, o il codice di Sonarr/Radarr del DTO.
  String _errorText(AppLocalizations l, Object? error, String? code) {
    if (code != null) {
      return switch (code) {
        'NotConfigured' => l.adminArrNotConfigured,
        'Unauthorized' => l.adminArrUnauthorized,
        _ => l.adminArrUnreachable,
      };
    }
    return error is DownloadsException
        ? downloadsFailureLabel(l, error.failure)
        : describeError(l, error ?? '');
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.search,
    required this.onAgain,
    required this.onAccept,
    required this.reviewing,
  });

  final DownloadSearch search;
  final VoidCallback onAgain;
  final VoidCallback? onAccept;
  final bool reviewing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = search.current;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(search.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        Text(l.downloadsRuntime(search.runtimeMinutes), style: muted),
        Text(
            current == null
                ? l.downloadsNoFile
                : l.downloadsCurrentFile(
                    formatGb(l, current.sizeBytes), current.score, current.quality),
            style: muted),
        Text(l.downloadsValidOf(search.validCount, search.totalCount),
            style: muted),
        OutlinedButton(onPressed: onAgain, child: Text(l.downloadsSearchAgain)),
        if (reviewing)
          FilledButton(onPressed: onAccept, child: Text(l.downloadsAccept)),
      ],
    );
  }
}

// Colonne della tabella (largo): rango, release, punteggio, peso, seeders,
// indexer, pulsante.
const _colRank = 32.0;
const _colScore = 80.0;
const _colSize = 90.0;
const _colSeeders = 80.0;
const _colButton = 110.0;

class _TableHead extends StatelessWidget {
  const _TableHead();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const style = TextStyle(color: WfColors.creamMuted, fontSize: 12);
    Widget cell(String text, {double? width, int flex = 0}) => width != null
        ? SizedBox(width: width, child: Text(text, style: style))
        : Expanded(flex: flex, child: Text(text, style: style));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        const SizedBox(width: _colRank),
        cell(l.downloadsColRelease, flex: 4),
        cell(l.downloadsColScore, width: _colScore),
        cell(l.downloadsColSize, width: _colSize),
        cell(l.downloadsColSeeders, width: _colSeeders),
        cell(l.downloadsColIndexer, flex: 2),
        const SizedBox(width: _colButton),
      ]),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({super.key, required this.candidate, required this.onGrab});

  final DownloadCandidate candidate;
  final VoidCallback? onGrab;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = candidate.release;
    final compact = FormFactor.of(context).compact;
    final button = FilledButton(onPressed: onGrab, child: Text(l.downloadsGrab));
    final size = formatGb(l, r.sizeBytes);
    final seeders = r.seeders?.toString() ?? '-';
    final name = Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis);
    final main = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${candidate.rank}. ${r.title}'),
              const SizedBox(height: 4),
              Text(
                  '${l.downloadsColScore} ${r.score} · $size · '
                  '${l.downloadsColSeeders} $seeders · ${r.indexer}',
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 13)),
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: button),
            ],
          )
        : Row(children: [
            SizedBox(width: _colRank, child: Text('${candidate.rank}')),
            Expanded(flex: 4, child: name),
            SizedBox(width: _colScore, child: Text('${r.score}')),
            SizedBox(width: _colSize, child: Text(size)),
            SizedBox(width: _colSeeders, child: Text(seeders)),
            Expanded(flex: 2, child: Text(r.indexer)),
            SizedBox(
                width: _colButton,
                child: Align(
                    alignment: AlignmentDirectional.centerEnd, child: button)),
          ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Come la bozza: la scelta della regola ha lo sfondo del film.
        color: candidate.isChoice ? WfColors.calendarMovie : WfColors.surface,
        border: Border.all(
            color: candidate.isChoice ? WfColors.gold : WfColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          main,
          if (candidate.isChoice)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(choiceWhy(l, candidate),
                  style: const TextStyle(color: WfColors.gold, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _RejectedRow extends StatelessWidget {
  const _RejectedRow({required this.rejected});

  final DownloadRejected rejected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = rejected.release;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.title,
              style: const TextStyle(color: WfColors.creamMuted),
              overflow: TextOverflow.ellipsis),
          Text(
              '${formatGb(l, r.sizeBytes)} · ${r.indexer} · '
              '${rejectedLabel(l, rejected)}',
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
