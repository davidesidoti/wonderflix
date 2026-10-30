import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/space/space_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_image.dart';
import '../detail/detail_providers.dart';
import '../downloads/download_search_page.dart';
import '../playback/play_launcher.dart';
import 'space_actions.dart';
import 'space_controller.dart';
import 'space_labels.dart';
import 'space_rows.dart';

/// La scheda del titolo (spec U §8, decisione 3 del piano 30b): dettagli,
/// chi l'ha visto e chiesto, segnali e i pulsanti Elimina, Tienilo e, se
/// [canLighten], Alleggerisci.
Future<void> showSpaceTitle(
  BuildContext context,
  SpaceCandidate candidate, {
  required bool favoriteGenre,
  required bool canLighten,
}) => showWfDialog<void>(
  context,
  semanticLabel: candidate.title,
  maxWidth: 560,
  builder: (_) => _TitleBody(
    candidate: candidate,
    favoriteGenre: favoriteGenre,
    canLighten: canLighten,
  ),
);

/// La scheda ridotta di una riga di "Alleggerire" (spec U §8): stessa scheda,
/// con peso, eccesso e GB/ora, e solo Alleggerisci e Tienilo.
Future<void> showSpaceLighten(BuildContext context, SpaceLighten item) =>
    showWfDialog<void>(
      context,
      semanticLabel: item.title,
      maxWidth: 560,
      builder: (_) => _TitleBody(
        candidate: SpaceCandidate(
          key: item.key,
          kind: item.kind,
          title: item.title,
          seasonNumber: item.seasonNumber,
          itemId: item.itemId,
          posterUrl: item.posterUrl,
          sizeBytes: item.sizeBytes,
          freeNowBytes: 0,
          freeLaterBytes: 0,
          inPackBytes: 0,
          via: const [],
          keep: const [],
          viewers: const [],
          requests: const [],
          ratingCount: 0,
          genres: const [],
        ),
        favoriteGenre: false,
        canLighten: true,
        lighten: item,
      ),
    );

class _TitleBody extends ConsumerStatefulWidget {
  const _TitleBody({
    required this.candidate,
    required this.favoriteGenre,
    required this.canLighten,
    this.lighten,
  });

  final SpaceCandidate candidate;
  final bool favoriteGenre;
  final bool canLighten;

  /// Valorizzato per la scheda ridotta di "Alleggerire".
  final SpaceLighten? lighten;

  @override
  ConsumerState<_TitleBody> createState() => _TitleBodyState();
}

class _TitleBodyState extends ConsumerState<_TitleBody> {
  /// Elimina in corso: una seconda pressione non fa ripartire la conferma.
  bool _busy = false;

  /// "Tienilo" in corso: rotellina sul pulsante, gli altri spenti.
  bool _keeping = false;

  SpaceCandidate get candidate => widget.candidate;

  @override
  Widget build(BuildContext context) {
    final favoriteGenre = widget.favoriteGenre;
    final canLighten = widget.canLighten;
    final lighten = widget.lighten;
    final l = AppLocalizations.of(context);
    final c = candidate;
    final title = spaceTitleOf(l, c.title, c.seasonNumber);
    final itemId = c.itemId;
    // Senza ItemId, o se la lettura fallisce, resta il resto della scheda.
    final item = itemId == null ? null : ref.watch(itemProvider(itemId)).value;
    final overview = item?.overview;
    final genres = item != null && item.genres.isNotEmpty
        ? item.genres
        : c.genres;
    final hasTrailer =
        item != null &&
        (item.localTrailerCount > 0 || remoteTrailerUri(item) != null);
    final now = clock.now();
    final poster = c.posterUrl;
    final signals = [...spaceViaLines(l, c, now), ...spaceKeepLabels(l, c)];
    final date = DateFormat.yMMMd(l.localeName);
    final facts = [
      if (c.year != null) '${c.year}',
      spaceGb(l, c.sizeBytes),
      if (lighten != null)
        l.spaceLightenFacts(
          spaceGb(l, lighten.excessBytes),
          NumberFormat('0.0', l.localeName).format(lighten.gbPerHour),
        ),
    ].join(' · ');
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                height: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: WfImage(
                    image: poster == null ? null : ImageRef(poster),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(facts, style: muted),
                    if (genres.isNotEmpty || favoriteGenre)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (favoriteGenre) l.spaceTopGenre,
                            ...genres,
                          ].join(' · '),
                          style: muted,
                        ),
                      ),
                    if (hasTrailer)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: WfButton.secondary(
                          label: l.actionTrailer,
                          icon: LucideIcons.clapperboard,
                          onPressed: () =>
                              unawaited(playTrailer(context, ref, item)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (overview != null && overview.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(overview, maxLines: 6, overflow: TextOverflow.ellipsis),
          ],
          if (c.viewers.isNotEmpty) ...[
            heading(l.spaceViewersTitle),
            for (final v in c.viewers)
              Text(
                [
                  v.finished
                      ? l.spaceViewerFinished(v.name)
                      : l.spaceViewerNotFinished(v.name),
                  if (v.lastPlayed != null)
                    date.format(v.lastPlayed!.toLocal()),
                ].join(', '),
                style: muted,
              ),
          ],
          if (c.requests.isNotEmpty) ...[
            heading(l.spaceRequestsTitle),
            for (final r in c.requests)
              Text(
                l.spaceRequestLine(r.name, date.format(r.at.toLocal())),
                style: muted,
              ),
          ],
          if (c.ratingAvg != null && c.ratingCount > 0) ...[
            heading(l.spaceRatingTitle),
            Text(
              l.spaceRatingLine(
                NumberFormat('0.0', l.localeName).format(c.ratingAvg),
                c.ratingCount,
              ),
              style: muted,
            ),
          ],
          if (signals.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final s in signals) Text(s, style: muted),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (canLighten)
                WfButton.secondary(
                  label: l.spaceLightenAction,
                  icon: LucideIcons.minimize2,
                  onPressed: _busy || _keeping
                      ? null
                      : () => unawaited(_lighten(context, ref, title)),
                ),
              WfButton.secondary(
                key: const ValueKey('space-keep'),
                label: l.spaceDialogKeep,
                icon: LucideIcons.shield,
                // Il plugin risponde e la panoramica si rilegge: intanto la
                // rotellina dice che sta lavorando.
                overlay: _keeping
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                onPressed: _busy || _keeping
                    ? null
                    : () => unawaited(_keep(context, ref, title)),
              ),
              if (lighten == null)
                WfButton.primary(
                  label: l.spaceDialogDelete,
                  icon: LucideIcons.trash2,
                  onPressed: _busy || _keeping
                      ? null
                      : () => unawaited(_delete(context, ref, title)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    setState(() => _busy = true);
    final started = await startSpaceOperation(
      context,
      ref,
      kind: candidate.kind,
      key: candidate.key,
      title: title,
      candidate: candidate,
    );
    if (!context.mounted) return;
    if (started) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _keep(BuildContext context, WidgetRef ref, String title) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _keeping = true);
    final failure = await ref
        .read(spaceControllerProvider.notifier)
        .keep(candidate.key, title);
    if (mounted) setState(() => _keeping = false);
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(spaceFailureLabel(l, failure))),
      );
    } else if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _lighten(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    await showDownloadSearch(context, candidate.key, title, lighten: true);
    if (context.mounted) {
      await ref.read(spaceControllerProvider.notifier).reload();
    }
  }
}
