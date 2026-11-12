import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/space/space_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_image.dart';
import '../admin/admin_confirm_dialog.dart';
import '../admin/admin_kit.dart';
import '../admin/admin_widgets.dart';
import '../social/social_providers.dart';
import '../space/space_labels.dart';
import '../space/space_providers.dart';
import 'download_labels.dart';
import 'download_search_controller.dart';
import 'weight_ruler.dart';

/// La pagina a tutto schermo con le release di un titolo (spec T §8.2).
/// [reviewing]: aperta da "Da ripassare", con "Va bene così". [lighten]: da
/// "Alleggerisci", il titolo scaricato resta "va bene così" (niente upgrade
/// automatici). [image]: lo sfondo della testa, [blurImage] per le locandine
/// (sfocate), non per i backdrop.
Future<void> showDownloadSearch(
  BuildContext context,
  String key,
  String title, {
  bool reviewing = false,
  bool lighten = false,
  ImageRef? image,
  bool blurImage = false,
}) =>
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => Dialog.fullscreen(
        child: _SearchPage(
            dlKey: key,
            title: title,
            reviewing: reviewing,
            lighten: lighten,
            image: image,
            blurImage: blurImage),
      ),
    );

/// La spia dei seeders: spenta a 0 o sconosciuti, oro da 1 a 9, verde da 10.
LampState seedersLamp(int? seeders) => switch (seeders) {
      null || <= 0 => LampState.off,
      < 10 => LampState.attention,
      _ => LampState.ok,
    };

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
    required this.image,
    required this.blurImage,
  });

  final String dlKey;
  final String title;
  final bool reviewing;
  final bool lighten;
  final ImageRef? image;
  final bool blurImage;

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
    void viaArr() => unawaited(ref.read(provider.notifier).searchViaArr());
    final running = ref.watch(downloadSearchRunningProvider(dlKey));
    final jobs = ref.watch(socialAvailabilityProvider).downloadsSearchJobs;
    // Con la ricerca in background, tre errori di rete di fila: "Riprova"
    // riprende a chiedere lo stato senza rilanciare la ricerca.
    final pollingFailed = jobs &&
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
      // La scelta da sola sopra la tabella; con Alleggerisci, se è il file
      // che c'è già, resta in tabella senza "Scarica".
      final pick = search.candidates
          .where((c) => c.isChoice && !(lighten && search.isCurrentFile(c.release)))
          .firstOrNull;
      final rows = [
        for (final c in search.candidates)
          if (c != pick) c,
      ];
      final maxScore =
          search.candidates.fold(0, (m, c) => math.max(m, c.release.score));
      final marks = rulerMarks(search);
      final freed = freedBytes(search);
      return Scaffold(
        body: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            _Hero(search: search, image: image, blur: blurImage),
            Padding(
              padding: EdgeInsets.fromLTRB(margin, 12, margin, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          _Actions(
            search: search,
            onAgain: busy ? null : again,
            // Solo un plugin con le ricerche in background conosce l'Engine.
            showViaArr: jobs,
            onViaArr: busy ? null : viaArr,
            onAccept: reviewing && !busy ? () => _accept(context, ref) : null,
            reviewing: reviewing,
            onAtMinimum: busy ? null : () => _markAtMinimum(context, ref),
            lighten: lighten,
          ),
          const SizedBox(height: 16),
          if (search.engine == SearchEngine.prowlarr && search.lowResults)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(l.downloadsLowResults(_arrService(search)),
                  style: const TextStyle(color: WfColors.creamMuted)),
            ),
          if (lighten && search.current != null && !search.hasLighter)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(l.downloadsNothingLighter(search.current!.score),
                  style: const TextStyle(color: WfColors.creamMuted)),
            ),
          if (marks.length >= 2) ...[
            AdminSectionTitle(
                title: l.downloadsWeightsTitle, note: l.downloadsWeightsHint),
            WeightRuler(marks: marks, currentBytes: search.current?.sizeBytes),
            const SizedBox(height: 8),
          ],
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
          if (pick != null) ...[
            AdminSectionTitle(title: l.downloadsRuleChoiceTitle),
            _ChoiceBlock(
              key: ValueKey('candidate-${pick.release.guid}'),
              search: search,
              candidate: pick,
              freedBytes: freed,
              onGrab: busy
                  ? null
                  : () => _grab(context, ref, search.current?.score,
                      pick.release,
                      wouldImport: pick.wouldImport),
            ),
          ],
          if (rows.isNotEmpty) ...[
            AdminSectionTitle(title: l.downloadsAllReleases, count: rows.length),
            if (!FormFactor.of(context).compact) const _TableHead(),
          ],
          for (final c in rows)
            _CandidateRow(
              key: ValueKey('candidate-${c.release.guid}'),
              candidate: c,
              maxScore: maxScore,
              isCurrent: lighten && search.isCurrentFile(c.release),
              onGrab: busy
                  ? null
                  : () => _grab(context, ref, search.current?.score, c.release,
                      wouldImport: c.wouldImport),
            ),
          if (search.rejected.isNotEmpty)
            _RejectedSection(rejected: search.rejected),
                ],
              ),
            ),
          ],
        ),
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
  String _elapsed([DateTime? since]) {
    final seconds =
        clock.now().difference(since ?? widget.running.startedAt).inSeconds;
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// La riga mentre la ricerca aspetta quella automatica in corso.
  String _waiting(AppLocalizations l, DownloadSearchWaiting w) {
    final elapsed = _elapsed(w.since);
    final typical = w.typicalSeconds;
    if (typical == null) return l.downloadsSearchWaitingFor(w.title, elapsed);
    final text =
        typical < 60 ? '~$typical s' : '~${(typical / 60).round()} min';
    return l.downloadsSearchWaitingForTypical(w.title, elapsed, text);
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
            Text(
              switch (widget.running.waitingFor) {
                final w? => _waiting(l, w),
                null =>
                  l.downloadsSearchRunning(widget.running.service, _elapsed()),
              },
              textAlign: TextAlign.center,
            ),
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

/// Il servizio che cerca "alla vecchia maniera" questo titolo.
String _arrService(DownloadSearch search) =>
    search.kind == DownloadKind.movie ? 'Radarr' : 'Sonarr';

/// La testa: lo sfondo del titolo col velo, "← Download", il titolo, la riga
/// meta e la scheda tecnica del file attuale (sotto, nello stretto).
class _Hero extends StatelessWidget {
  const _Hero({required this.search, required this.image, required this.blur});

  final DownloadSearch search;
  final ImageRef? image;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final compact = FormFactor.of(context).compact;
    final margin = adminSideMargin(context);
    final inset = MediaQuery.paddingOf(context).top;
    final image = this.image;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    final spec = _SpecCard(search: search);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Altezza minima, non fissa: un titolo lungo allunga la testa invece
        // di salire sopra "← Download".
        Stack(
          children: [
            const Positioned.fill(
                child: ColoredBox(color: WfColors.surfaceHigh)),
            if (image != null)
              Positioned.fill(
                child: ClipRect(
                  child: blur
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: WfImage(image: image, fallbackIcon: null))
                      : WfImage(image: image, fallbackIcon: null),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [WfColors.bg, WfColors.bg.withValues(alpha: 0.25)],
                    stops: const [0.08, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(margin, inset + 8, margin, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    offset: const Offset(-8, 0),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                          foregroundColor: WfColors.creamMuted),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.arrowLeft, size: 16),
                      label: Text(l.adminTabDownloads),
                    ),
                  ),
                  ConstrainedBox(
                    // 40: il pulsante; 24: i margini sopra e sotto.
                    constraints: BoxConstraints(
                        minHeight: (compact ? 150 : 190) - 40 - 24),
                    child: Align(
                      alignment: AlignmentDirectional.bottomStart,
                      child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(search.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: WfText.display(compact ? 32 : 44)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 18, runSpacing: 4, children: [
                            Text(l.downloadsRuntime(search.runtimeMinutes),
                                style: muted),
                            Text(
                                l.downloadsValidOf(
                                    search.validCount, search.totalCount),
                                style: muted),
                            if (search.engine == SearchEngine.arr)
                              Text(l.downloadsResultsFromArr(
                                      _arrService(search)),
                                  style: muted),
                          ]),
                        ],
                      ),
                    ),
                    if (!compact) ...[const SizedBox(width: 20), spec],
                  ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (compact)
          Padding(
              padding: EdgeInsets.fromLTRB(margin, 12, margin, 0),
              child: spec),
      ],
    );
  }
}

/// La "scheda tecnica" del file attuale: peso, punteggio e qualità, GB/ora.
class _SpecCard extends StatelessWidget {
  const _SpecCard({required this.search});

  final DownloadSearch search;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = search.current;
    final rate = current == null ? null : gbPerHour(search, current.sizeBytes);
    return Container(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WfColors.surface.withValues(alpha: 0.85),
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: current == null
          ? Text(l.downloadsNoFile,
              style: const TextStyle(color: WfColors.creamMuted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatGb(l, current.sizeBytes),
                    style: WfText.display(26)),
                Text(
                    '${l.downloadsColScore} ${current.score} · '
                    '${current.quality}',
                    style: const TextStyle(
                        color: WfColors.creamMuted, fontSize: 12)),
                if (rate != null)
                  Text(gbPerHourLabel(l, rate),
                      style:
                          const TextStyle(color: WfColors.gold, fontSize: 12)),
              ],
            ),
    );
  }
}

/// La riga delle azioni sotto la testa; "Cerca su MIRCrew" a destra.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.search,
    required this.onAgain,
    required this.showViaArr,
    required this.onViaArr,
    required this.onAccept,
    required this.reviewing,
    required this.onAtMinimum,
    required this.lighten,
  });

  final DownloadSearch search;
  final VoidCallback? onAgain;
  final bool showViaArr;
  final VoidCallback? onViaArr;
  final VoidCallback? onAccept;
  final bool reviewing;
  final VoidCallback? onAtMinimum;
  final bool lighten;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = search.current;
    final external = search.externalSearchUrl;
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton(onPressed: onAgain, child: Text(l.downloadsSearchAgain)),
        if (showViaArr)
          OutlinedButton(
              onPressed: onViaArr,
              child: Text(l.downloadsSearchWithArr(_arrService(search)))),
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
    // Come prima: MIRCrew solo quando non c'è niente da scaricare.
    if (search.candidates.isNotEmpty || external == null) return buttons;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      children: [
        buttons,
        OutlinedButton(
          onPressed: () => openExternalSearch(context, external),
          child: Text(l.downloadsExternalSearch),
        ),
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
    this.maxScore,
  });

  final DownloadCandidate candidate;
  final VoidCallback? onGrab;

  /// È il file che c'è già: niente da scaricare, anche se è la scelta.
  final bool isCurrent;

  /// Al posto del rango (per "E12" nel riquadro dei migliori episodi).
  final String? rankText;

  /// Il punteggio più alto della tabella, per la barretta; null: niente.
  final int? maxScore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = candidate.release;
    final compact = FormFactor.of(context).compact;
    final top = maxScore;
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
                width: _colRank,
                child: Text(rankText ?? '${candidate.rank}',
                    style: WfText.display(18, color: WfColors.creamMuted))),
            Expanded(flex: 4, child: name),
            SizedBox(
                width: _colScore,
                child: Row(children: [
                  if (top != null && top > 0) ...[
                    Container(
                      width: 40 * (r.score / top).clamp(0.0, 1.0),
                      height: 4,
                      decoration: BoxDecoration(
                          color: WfColors.gold,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(child: Text('${r.score}')),
                ])),
            SizedBox(width: _colSize, child: Text(size)),
            SizedBox(
                width: _colSeeders,
                child: _Seeders(seeders: r.seeders)),
            Expanded(
                flex: 2,
                child: Text(r.indexer,
                    style: const TextStyle(color: WfColors.creamMuted))),
            SizedBox(
                width: _colButton,
                child: button == null
                    ? null
                    : Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: button)),
          ]);
    final row = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WfColors.surface,
        border: Border.all(color: WfColors.border),
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
            ),
        ],
      ),
    );
    return isCurrent ? Opacity(opacity: 0.6, child: row) : row;
  }
}

/// La spia e il numero dei seeders ("-" se sconosciuti).
class _Seeders extends StatelessWidget {
  const _Seeders({required this.seeders, this.suffix});

  final int? seeders;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final n = seeders?.toString() ?? '-';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      WfLamp(
          state: seedersLamp(seeders),
          label: '${l.downloadsColSeeders} $n',
          size: 8),
      const SizedBox(width: 5),
      Flexible(child: Text(suffix == null ? n : '$n $suffix')),
    ]);
  }
}

/// La scelta della regola, da sola sopra la tabella (spec "La ricerca
/// manuale"): lo stesso "Scarica" e le stesse conferme di [_CandidateRow].
class _ChoiceBlock extends StatelessWidget {
  const _ChoiceBlock({
    super.key,
    required this.search,
    required this.candidate,
    required this.freedBytes,
    required this.onGrab,
  });

  final DownloadSearch search;
  final DownloadCandidate candidate;
  final int? freedBytes;
  final VoidCallback? onGrab;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = candidate.release;
    final compact = FormFactor.of(context).compact;
    final rate = gbPerHour(search, r.sizeBytes);
    final freed = freedBytes;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    const gold = TextStyle(color: WfColors.gold, fontSize: 12);
    final rank =
        Text('${candidate.rank}', style: WfText.display(30, color: WfColors.gold));
    final button = FilledButton(
        style: _compactButton, onPressed: onGrab, child: Text(l.downloadsGrab));
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(r.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        DefaultTextStyle.merge(
          style: muted,
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${l.downloadsColScore} ${r.score}'),
              Text([
                formatGb(l, r.sizeBytes),
                if (rate != null) gbPerHourLabel(l, rate),
              ].join(', ')),
              _Seeders(seeders: r.seeders, suffix: l.downloadsColSeeders),
              Text(r.indexer),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          Text(choiceWhy(l, candidate), style: gold),
          if (freed != null)
            Text(l.downloadsFrees(formatGb(l, freed)), style: gold),
        ]),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WfColors.calendarMovie,
        border: Border.all(color: WfColors.gold),
        borderRadius: BorderRadius.circular(6),
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                rank,
                const SizedBox(width: 12),
                Expanded(child: details),
              ]),
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: button),
            ])
          : Row(children: [
              rank,
              const SizedBox(width: 16),
              Expanded(child: details),
              const SizedBox(width: 16),
              button,
            ]),
    );
  }
}

/// Gli scartati, chiusi: un riepilogo per motivo e "Mostra" per l'elenco.
class _RejectedSection extends StatefulWidget {
  const _RejectedSection({required this.rejected});

  final List<DownloadRejected> rejected;

  @override
  State<_RejectedSection> createState() => _RejectedSectionState();
}

class _RejectedSectionState extends State<_RejectedSection> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final counts = <String, int>{};
    for (final r in widget.rejected) {
      // Per motivo, senza il dettaglio della singola release; Sonarr/Radarr
      // hanno solo il dettaglio come motivo.
      final label = switch (r.reason) {
        RejectedReason.tooSmall => l.downloadsRejectedTooSmallShort,
        RejectedReason.arr || RejectedReason.unknown => rejectedLabel(l, r),
        _ => rejectedLabel(
            l, DownloadRejected(release: r.release, reason: r.reason)),
      };
      counts.update(label, (n) => n + 1, ifAbsent: () => 1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionTitle(
          title: l.downloadsRejectedTitle,
          count: widget.rejected.length,
          action: _shown
              ? null
              : TextButton(
                  onPressed: () => setState(() => _shown = true),
                  child: Text(l.downloadsShow)),
        ),
        if (_shown)
          for (final r in widget.rejected) _RejectedRow(rejected: r)
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final MapEntry(:key, :value) in counts.entries)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: WfColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '$value',
                        style: const TextStyle(
                            color: WfColors.cream,
                            fontWeight: FontWeight.w600)),
                    TextSpan(text: ' $key'),
                  ]),
                  style:
                      const TextStyle(color: WfColors.creamMuted, fontSize: 13),
                ),
              ),
          ]),
      ],
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
