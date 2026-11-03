import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../../core/space/space_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../admin/admin_confirm_dialog.dart';
import '../admin/admin_widgets.dart';
import '../social/social_providers.dart';
import '../space/space_labels.dart';
import '../space/space_providers.dart';
import 'download_labels.dart';
import 'download_search_controller.dart';

/// La pagina a tutto schermo con le release di un titolo (spec T §8.2).
/// [reviewing]: aperta da "Da ripassare", con "Va bene così". [lighten]: da
/// "Alleggerisci", il titolo scaricato resta "va bene così" (niente upgrade
/// automatici).
Future<void> showDownloadSearch(
  BuildContext context,
  String key,
  String title, {
  bool reviewing = false,
  bool lighten = false,
}) =>
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => Dialog.fullscreen(
        child: _SearchPage(
            dlKey: key, title: title, reviewing: reviewing, lighten: lighten),
      ),
    );

/// Apre nel browser la ricerca sul tracker esterno; se non parte lo dice.
Future<void> openExternalSearch(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = AppLocalizations.of(context).downloadsExternalSearchFailed;
  final uri = Uri.tryParse(url);
  var opened = false;
  // L'URL viene dal plugin: solo pagine web.
  if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
  }
  if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
}

class _SearchPage extends ConsumerWidget {
  const _SearchPage({
    required this.dlKey,
    required this.title,
    required this.reviewing,
    required this.lighten,
  });

  final String dlKey;
  final String title;
  final bool reviewing;
  final bool lighten;

  /// Un errore dopo un'azione: la pagina resta, con il messaggio.
  void _fail(BuildContext context, DownloadsFailure failure) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(downloadsFailureLabel(
            AppLocalizations.of(context), failure)),
      ));

  /// [currentScore]: il punteggio del file con cui confrontare (null: nessun
  /// confronto). [sonarr]: un episodio di una stagione, il testo dice Sonarr.
  Future<void> _grab(BuildContext context, WidgetRef ref, int? currentScore,
      DownloadRelease release,
      {required bool wouldImport, bool sonarr = false}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(downloadSearchControllerProvider(dlKey).notifier);
    // Decisione 5: conferma se non migliora il file attuale o non si importa.
    final reasons = [
      if (currentScore != null && release.score <= currentScore)
        l.downloadsConfirmLowerScore(release.score, currentScore),
      if (!wouldImport)
        sonarr ? l.downloadsConfirmNoImportSonarr : l.downloadsConfirmNoImport,
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
    final (:failure, :existing) =
        await controller.grabOrExisting(release, lighten: lighten);
    if (!context.mounted) return;
    if (failure == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.downloadsStarted)));
      navigator.pop();
      return;
    }
    if (existing == null) return _fail(context, failure);
    // Il torrent è già in qBittorrent: si offre di importarne i file.
    final ok = await showAdminConfirmDialog(
      context,
      title: l.downloadsExistingTorrentTitle,
      message: l.downloadsExistingTorrentMessage(existing.name),
      confirmLabel: l.downloadsExistingTorrentImport,
    );
    if (!ok || !context.mounted) return;
    final importFailure = await controller.importExisting(existing.hash, lighten: lighten);
    if (!context.mounted) return;
    if (importFailure != null) return _fail(context, importFailure);
    messenger
        .showSnackBar(SnackBar(content: Text(l.downloadsExistingTorrentStarted)));
    navigator.pop();
  }

  /// "Scarica tutti" del riquadro "Migliori episodi" (decisione 4 del piano 29c).
  Future<void> _grabAll(BuildContext context, WidgetRef ref,
      List<DownloadEpisodeChoice> choices) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(downloadSearchControllerProvider(dlKey).notifier);
    // Decisione 4: una sola conferma se qualche episodio non migliora il suo
    // file o non verrebbe importato.
    final lower = choices.where((c) => c.lowersScore).length;
    final noImport = choices.where((c) => !c.wouldImport).length;
    if (lower > 0 || noImport > 0) {
      final ok = await showAdminConfirmDialog(
        context,
        title: l.downloadsGrabAllConfirmTitle,
        message: [
          if (lower > 0) l.downloadsGrabAllConfirmLowerScore(lower),
          if (noImport > 0) l.downloadsGrabAllConfirmNoImport(noImport),
        ].join('\n'),
        confirmLabel: l.downloadsGrab,
      );
      if (!ok || !context.mounted) return;
    }
    final result = await controller.grabAll(
        [for (final c in choices) c.release!],
        lighten: lighten);
    // Pagina chiusa durante la serie: niente da dire a nessuno.
    if (!context.mounted) return;
    if (result.failed == 0) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.downloadsGrabAllDone(result.started))));
      navigator.pop();
      return;
    }
    // La pagina resta: l'admin vede i motivi e può riprovare.
    messenger.showSnackBar(SnackBar(
      content: Text(l.downloadsGrabAllPartial(
          result.started,
          result.failed,
          downloadsFailureLabel(l, result.firstFailure!))),
    ));
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final failure = await ref
        .read(downloadSearchControllerProvider(dlKey).notifier)
        .accept();
    if (!context.mounted) return;
    if (failure != null) return _fail(context, failure);
    Navigator.of(context).pop();
  }

  /// "Già al minimo": il titolo esce da Alleggerire; si annulla dai Tenuti.
  Future<void> _markAtMinimum(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(spaceApiProvider).markAtMinimum(dlKey, title);
    } on SpaceException catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(spaceFailureLabel(l, e.failure))));
      return;
    }
    if (context.mounted) Navigator.of(context).pop();
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
    final running = ref.watch(downloadSearchRunningProvider(dlKey));
    // Con la ricerca in background, tre errori di rete di fila: "Riprova"
    // riprende a chiedere lo stato senza rilanciare la ricerca.
    final pollingFailed = ref.watch(socialAvailabilityProvider).downloadsSearchJobs &&
        state.error is DownloadsException &&
        (state.error! as DownloadsException).failure == DownloadsFailure.network;

    Widget body;
    if (state.isLoading) {
      body = running != null
          ? _SearchRunning(running: running)
          : Center(
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
            if (pollingFailed)
              TextButton(
                  onPressed: () => unawaited(ref.read(provider.notifier).retry()),
                  child: Text(l.downloadsSearchRetry))
            else
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
            onAgain: busy ? null : again,
            onAccept: reviewing && !busy ? () => _accept(context, ref) : null,
            reviewing: reviewing,
            onAtMinimum: busy ? null : () => _markAtMinimum(context, ref),
            lighten: lighten,
          ),
          const SizedBox(height: 16),
          if (lighten && search.current != null && !search.hasLighter)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(l.downloadsNothingLighter(search.current!.score),
                  style: const TextStyle(color: WfColors.creamMuted)),
            ),
          if (search.episodeChoices.isNotEmpty)
            _BestEpisodes(
              choices: search.episodeChoices,
              busy: busy,
              progress: ref.watch(downloadGrabProgressProvider(dlKey)),
              onGrab: (c) => _grab(context, ref, c.currentScore, c.release!,
                  wouldImport: c.wouldImport, sonarr: true),
              onGrabAll: (withRelease) => _grabAll(context, ref, withRelease),
            ),
          if (search.candidates.isEmpty) AdminEmptyText(text: l.downloadsNothingYet),
          if (search.candidates.isEmpty && search.externalSearchUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  onPressed: () =>
                      openExternalSearch(context, search.externalSearchUrl!),
                  child: Text(l.downloadsExternalSearch),
                ),
              ),
            ),
          if (search.candidates.isNotEmpty &&
              !FormFactor.of(context).compact)
            const _TableHead(),
          for (final c in search.candidates)
            _CandidateRow(
              key: ValueKey('candidate-${c.release.guid}'),
              candidate: c,
              isCurrent: lighten && search.isCurrentFile(c.release),
              onGrab: busy
                  ? null
                  : () => _grab(context, ref, search.current?.score, c.release,
                      wouldImport: c.wouldImport),
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

/// La ricerca in background in corso: barra indeterminata e tempo che scorre
/// (spec W §5.3).
class _SearchRunning extends StatefulWidget {
  const _SearchRunning({required this.running});

  final DownloadSearchRunning running;

  @override
  State<_SearchRunning> createState() => _SearchRunningState();
}

class _SearchRunningState extends State<_SearchRunning> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// m:ss, i minuti oltre 59 senza ore. Un `startedAt` nel futuro (orologio
  /// avanti rispetto al server) dà 0:00.
  String _elapsed() {
    final seconds = clock.now().difference(widget.running.startedAt).inSeconds;
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.downloadsSearchRunning(widget.running.service, _elapsed())),
            if (widget.running.reconnecting) ...[
              const SizedBox(height: 8),
              Text(l.downloadsSearchReconnecting, style: muted),
            ],
            const SizedBox(height: 8),
            Text(l.downloadsSearchRunningHint,
                textAlign: TextAlign.center, style: muted),
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.search,
    required this.onAgain,
    required this.onAccept,
    required this.reviewing,
    required this.onAtMinimum,
    required this.lighten,
  });

  final DownloadSearch search;
  final VoidCallback? onAgain;
  final VoidCallback? onAccept;
  final bool reviewing;
  final VoidCallback? onAtMinimum;
  final bool lighten;

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
        if (lighten && current != null)
          OutlinedButton(
              onPressed: onAtMinimum, child: Text(l.downloadsAtMinimum)),
        if (reviewing)
          FilledButton(
              style: _compactButton,
              onPressed: onAccept,
              child: Text(l.downloadsAccept)),
      ],
    );
  }
}

// Il tema dà ai FilledButton la larghezza piena: qui servono della misura del testo.
final _compactButton = FilledButton.styleFrom(minimumSize: const Size(0, 40));

// Colonne della tabella (largo): rango (o "E12"), release, punteggio, peso,
// seeders, indexer, pulsante.
const _colRank = 44.0;
const _colScore = 80.0;
const _colSize = 90.0;
const _colSeeders = 80.0;
const _colButton = 140.0;

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

/// Il riquadro "Migliori episodi" (spec T §8.2): il singolo scelto di ogni
/// episodio e "Scarica tutti". Le righe sono quelle della lista completa.
class _BestEpisodes extends StatelessWidget {
  const _BestEpisodes({
    required this.choices,
    required this.busy,
    required this.progress,
    required this.onGrab,
    required this.onGrabAll,
  });

  final List<DownloadEpisodeChoice> choices;
  final bool busy;
  final (int, int)? progress;
  final void Function(DownloadEpisodeChoice) onGrab;
  final void Function(List<DownloadEpisodeChoice>) onGrabAll;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final withRelease = [
      for (final c in choices)
        if (c.release != null) c,
    ];
    final progress = this.progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l.downloadsBestEpisodes,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              if (withRelease.isNotEmpty)
                FilledButton(
                  style: _compactButton,
                  onPressed: busy ? null : () => onGrabAll(withRelease),
                  child: Text(progress == null
                      ? l.downloadsGrabAll(withRelease.length)
                      : l.downloadsGrabAllProgress(progress.$1, progress.$2)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!FormFactor.of(context).compact) const _TableHead(),
          for (final c in choices)
            if (c.release == null)
              _NoEpisodeRow(number: c.episodeNumber)
            else
              _CandidateRow(
                key: ValueKey('episode-${c.episodeNumber}'),
                candidate: DownloadCandidate(
                  rank: c.episodeNumber,
                  release: c.release!,
                  isChoice: false,
                  wouldImport: c.wouldImport,
                ),
                rankText: l.downloadsEpisodeShort(c.episodeNumber),
                onGrab: busy ? null : () => onGrab(c),
              ),
        ],
      ),
    );
  }
}

class _NoEpisodeRow extends StatelessWidget {
  const _NoEpisodeRow({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WfColors.surface,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        SizedBox(width: _colRank, child: Text(l.downloadsEpisodeShort(number))),
        Expanded(
          child: Text(l.downloadsEpisodeNone,
              style: const TextStyle(color: WfColors.creamMuted)),
        ),
      ]),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    super.key,
    required this.candidate,
    required this.onGrab,
    this.rankText,
    this.isCurrent = false,
  });

  final DownloadCandidate candidate;
  final VoidCallback? onGrab;

  /// È il file che c'è già: niente da scaricare, anche se è la scelta.
  final bool isCurrent;

  /// Al posto del rango (per "E12" nel riquadro dei migliori episodi).
  final String? rankText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = candidate.release;
    final compact = FormFactor.of(context).compact;
    final highlight = candidate.isChoice && !isCurrent;
    final button = isCurrent
        ? null
        : FilledButton(
            style: _compactButton,
            onPressed: onGrab,
            child: Text(l.downloadsGrab));
    final size = formatGb(l, r.sizeBytes);
    final seeders = r.seeders?.toString() ?? '-';
    final name = Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis);
    final main = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${rankText ?? '${candidate.rank}.'} ${r.title}'),
              const SizedBox(height: 4),
              Text(
                  '${l.downloadsColScore} ${r.score} · $size · '
                  '${l.downloadsColSeeders} $seeders · ${r.indexer}',
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 13)),
              if (button != null) ...[
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerEnd, child: button),
              ],
            ],
          )
        : Row(children: [
            SizedBox(
                width: _colRank, child: Text(rankText ?? '${candidate.rank}')),
            Expanded(flex: 4, child: name),
            SizedBox(width: _colScore, child: Text('${r.score}')),
            SizedBox(width: _colSize, child: Text(size)),
            SizedBox(width: _colSeeders, child: Text(seeders)),
            Expanded(flex: 2, child: Text(r.indexer)),
            SizedBox(
                width: _colButton,
                child: button == null
                    ? null
                    : Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: button)),
          ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Come la bozza: la scelta della regola ha lo sfondo del film.
        color: highlight ? WfColors.calendarMovie : WfColors.surface,
        border: Border.all(color: highlight ? WfColors.gold : WfColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          main,
          if (isCurrent)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l.downloadsIsCurrentFile,
                  style:
                      const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
            )
          else if (candidate.isChoice)
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
