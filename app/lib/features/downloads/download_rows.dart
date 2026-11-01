import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/downloads/download_models.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_image.dart';
import '../admin/admin_action_button.dart';
import '../admin/admin_time.dart';
import 'download_labels.dart';

/// Da questo punteggio in su una release è "a posto" (spec T §8.1).
const downloadGoodScore = 150;

/// Il punteggio come pastiglia: verde dal bersaglio in su, oro sotto.
class ScorePill extends StatelessWidget {
  const ScorePill({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= downloadGoodScore ? WfColors.online : WfColors.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$score',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// La base di una riga (anche della scheda Spazio): poster, testi e pulsanti (sotto nel layout stretto).
class RowShell extends StatelessWidget {
  const RowShell({
    super.key,
    required this.posterUrl,
    required this.lines,
    required this.actions,
    this.accent,
    this.onTap,
  });

  final String? posterUrl;
  final List<Widget> lines;
  final List<Widget> actions;

  /// Il colore del bordo ("Serve te").
  final Color? accent;

  /// Riga toccabile: l'evidenziazione resta dentro la scheda arrotondata.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final compact = FormFactor.of(context).compact;
    final url = posterUrl;
    final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
    final row = Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            height: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: WfImage(image: url == null ? null : ImageRef(url)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...lines,
                if (compact) ...[const SizedBox(height: 8), buttons],
              ],
            ),
          ),
          if (!compact) ...[const SizedBox(width: 12), buttons],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: WfColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: accent ?? WfColors.border),
        ),
        child: onTap == null ? row : InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// La barra sottile di avanzamento, uguale nelle schede Download e Spazio.
class RowProgressBar extends StatelessWidget {
  const RowProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 4,
            color: WfColors.gold,
            backgroundColor: WfColors.border,
          ),
        ),
      );
}

Widget _title(String text) => Text(text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontWeight: FontWeight.w600));

Widget _muted(String text, {Color color = WfColors.creamMuted}) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );

const _small = TextStyle(fontSize: 13);
const _smallMuted = TextStyle(color: WfColors.creamMuted, fontSize: 13);

/// Una scelta automatica recente (spec T §8.1): release, peso, punteggio,
/// indexer e quando; "upgrade" con prima → dopo, "scelta tua" se dell'admin.
class DownloadChoiceRow extends StatelessWidget {
  const DownloadChoiceRow({
    super.key,
    required this.choice,
    required this.now,
    required this.onChange,
  });

  final DownloadChoice choice;
  final DateTime now;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final release = choice.release;
    final previous = choice.previousScore;
    return RowShell(
      posterUrl: choice.posterUrl,
      lines: [
        _title(choice.title),
        _muted(release.title),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ScorePill(score: release.score),
              Text(formatGb(l, release.sizeBytes), style: _small),
              Text(release.indexer, style: _smallMuted),
              Text(adminTimeLabel(choice.at, now, l), style: _smallMuted),
              if (previous != null)
                Text(l.downloadsUpgrade('$previous', '${release.score}'),
                    style:
                        const TextStyle(color: WfColors.online, fontSize: 13)),
              if (choice.byAdmin)
                Text(l.downloadsByAdmin,
                    style:
                        const TextStyle(color: WfColors.gold, fontSize: 13)),
            ],
          ),
        ),
      ],
      actions: [
        AdminActionButton(
          label: l.downloadsChange,
          icon: LucideIcons.arrowLeftRight,
          onPressed: () async => onChange(),
        ),
      ],
    );
  }
}

/// Un titolo in attesa, in download, in controllo upgrade o che "serve te".
/// I pulsanti vengono da `item.actions` (spec "Serve te" §6); vuoti
/// (plugin 1.17.0) restano quelli di prima.
class DownloadItemRow extends StatelessWidget {
  const DownloadItemRow({
    super.key,
    required this.item,
    required this.now,
    required this.onAction,
  });

  final DownloadItem item;
  final DateTime now;
  final Future<void> Function(DownloadAction) onAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final needsYou = item.state == DownloadState.needsYou;
    final reason = item.reason;
    // Per "Serve te" il motivo è già nello stato.
    final why = needsYou || reason == null ? '' : downloadReasonLabel(l, reason);
    final next = nextSearchLabel(l, item.nextSearchAt, now);
    final since = l.downloadsSince(
        DateFormat.MMMd(l.localeName).format(item.availableSince.toLocal()));
    final service = item.kind == DownloadKind.movie ? 'Radarr' : 'Sonarr';
    final explanation = downloadExplanation(l, item, service);
    final blocked = item.blockedMessage;
    final progress = item.progress;
    final legacy = item.actions.isEmpty;
    final actions = legacy
        ? [DownloadAction.pick, if (!needsYou) DownloadAction.searchNow]
        : item.actions;
    return RowShell(
      posterUrl: item.posterUrl,
      accent: needsYou ? WfColors.error : null,
      lines: [
        if (item.snoozed)
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [_title(item.title), _Tag(l.downloadsSnoozedTag)],
          )
        else
          _title(item.title),
        _muted(downloadStateLabel(l, item),
            color: needsYou ? WfColors.error : WfColors.creamMuted),
        _muted([since, if (next.isNotEmpty) next].join(' · ')),
        if (why.isNotEmpty) _muted(why, color: WfColors.gold),
        if (progress != null && item.state == DownloadState.downloading) ...[
          if (!progress.isFetchingMetadata)
            RowProgressBar(value: progress.fraction),
          _muted(downloadProgressLabel(l, progress, now)),
        ],
        if (explanation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(explanation,
                style: const TextStyle(color: WfColors.cream, fontSize: 13)),
          ),
        if (needsYou && blocked != null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: WfColors.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(blocked,
                style: const TextStyle(
                    color: WfColors.creamMuted,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
      ],
      actions: [
        for (final (i, action) in actions.indexed)
          AdminActionButton(
            label: _actionLabel(l, action, needsYou: needsYou && !legacy),
            icon: _actionIcon(action),
            primary: i == 0 && needsYou && !legacy,
            busyLabel: action == DownloadAction.grabBest
                ? l.downloadsActionGrabBestBusy
                : null,
            onPressed: () => onAction(action),
          ),
      ],
    );
  }

  /// [needsYou]: "Guarda" diventa "Scegli tu" (spec "Serve te" §4).
  String _actionLabel(AppLocalizations l, DownloadAction a,
          {required bool needsYou}) =>
      switch (a) {
        DownloadAction.grabBest => l.downloadsActionGrabBest,
        DownloadAction.pick when !needsYou => l.downloadsWatch,
        DownloadAction.pick when item.reason == DownloadReason.grabRefused =>
          l.downloadsActionPickOther,
        DownloadAction.pick => l.downloadsActionPick,
        DownloadAction.searchNow => l.downloadsSearchNow,
        DownloadAction.snooze => l.downloadsActionSnooze,
        DownloadAction.import => l.downloadsActionImport,
        DownloadAction.discard => l.downloadsActionDiscard,
      };

  static IconData _actionIcon(DownloadAction a) => switch (a) {
        DownloadAction.grabBest => LucideIcons.download,
        DownloadAction.pick => LucideIcons.search,
        DownloadAction.searchNow => LucideIcons.refreshCw,
        DownloadAction.snooze => LucideIcons.bellOff,
        DownloadAction.import => LucideIcons.fileInput,
        DownloadAction.discard => LucideIcons.trash2,
      };
}

/// L'etichetta oro accanto al titolo ("senza avvisi").
class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: WfColors.gold.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(color: WfColors.gold, fontSize: 11)),
      );
}

/// Un file da ripassare: punteggio e peso di quello che c'è ora.
class ReviewRow extends StatelessWidget {
  const ReviewRow({super.key, required this.item, required this.onOpen});

  final ReviewItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return RowShell(
      posterUrl: item.posterUrl,
      lines: [
        _title(item.title),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ScorePill(score: item.score),
              Text(formatGb(l, item.sizeBytes), style: _small),
              Text(item.quality, style: _smallMuted),
            ],
          ),
        ),
      ],
      actions: [
        AdminActionButton(
          label: l.downloadsOpen,
          icon: LucideIcons.search,
          onPressed: () async => onOpen(),
        ),
      ],
    );
  }
}
