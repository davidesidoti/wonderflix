import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/space/space_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../admin/admin_action_button.dart';
import '../admin/admin_time.dart';
import '../downloads/download_rows.dart';
import 'space_labels.dart';

/// Il titolo di un candidato, con la stagione se è una stagione.
String spaceTitleOf(AppLocalizations l, String title, int? season) =>
    season == null ? title : '$title · ${l.spaceSeason(season)}';

String spaceDate(AppLocalizations l, DateTime at) =>
    DateFormat.MMMd(l.localeName).format(at.toLocal());

const _title = TextStyle(fontWeight: FontWeight.w600);
const _small = TextStyle(fontSize: 13);
const _muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
const _gold = TextStyle(color: WfColors.gold, fontSize: 13);

Widget _line(String text, [TextStyle style = _muted]) => Padding(
  padding: const EdgeInsets.only(top: 2),
  child: Text(text, style: style),
);

Widget _heading(String text) =>
    Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: _title);

Widget _chip(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.16),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Text(text, style: TextStyle(color: color, fontSize: 12)),
);

Widget _tappable(VoidCallback? onTap, Widget child) => onTap == null
    ? child
    : InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: child,
      );

/// Una riga di "Cancellare" (spec U §8). [showSeasonOnly]: dentro il gruppo
/// di una serie, dove basta "Stagione N".
class SpaceCandidateRow extends StatelessWidget {
  const SpaceCandidateRow({
    super.key,
    required this.candidate,
    required this.topGenres,
    required this.now,
    required this.onOpen,
    this.showSeasonOnly = false,
  });

  final SpaceCandidate candidate;
  final List<String> topGenres;
  final DateTime now;
  final VoidCallback onOpen;
  final bool showSeasonOnly;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = candidate;
    final season = c.seasonNumber;
    final title = showSeasonOnly && season != null
        ? l.spaceSeason(season)
        : spaceTitleOf(l, c.title, season);
    final laterAt = c.freeLaterAt;
    final later = c.freeLaterBytes <= 0
        ? null
        : laterAt == null
        ? l.spaceFreeLaterNoDate(spaceGb(l, c.freeLaterBytes))
        : l.spaceFreeLater(spaceGb(l, c.freeLaterBytes), spaceDate(l, laterAt));
    final keeps = spaceKeepLabels(l, c);
    final favorite = c.genres.any(topGenres.contains);
    return _tappable(
      onOpen,
      RowShell(
        posterUrl: c.posterUrl,
        lines: [
          _heading(title),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(spaceGb(l, c.sizeBytes), style: _small),
                Text(l.spaceFreeNow(spaceGb(l, c.freeNowBytes)), style: _muted),
                if (later != null) Text(later, style: _muted),
              ],
            ),
          ),
          for (final text in spaceViaLines(l, c, now)) _line(text),
          if (keeps.isNotEmpty || favorite)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final k in keeps)
                    _chip(l.spaceKeepTag(k), WfColors.online),
                  if (favorite) _chip(l.spaceTopGenre, WfColors.gold),
                ],
              ),
            ),
        ],
        actions: const [],
      ),
    );
  }
}

/// Le stagioni di una serie sotto un solo titolo, con i GB sommati; si apre e
/// si chiude (decisione 1 del piano 30b).
class SpaceSeriesGroup extends StatelessWidget {
  const SpaceSeriesGroup({
    super.key,
    required this.title,
    required this.posterUrl,
    required this.sizeBytes,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final String? posterUrl;
  final int sizeBytes;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tappable(
          onToggle,
          RowShell(
            posterUrl: posterUrl,
            lines: [_heading(title), _line(spaceGb(l, sizeBytes), _small)],
            actions: [
              Icon(
                expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 18,
                color: WfColors.creamMuted,
              ),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(children: children),
          ),
      ],
    );
  }
}

/// Una riga di "Alleggerire".
class SpaceLightenRow extends StatelessWidget {
  const SpaceLightenRow({
    super.key,
    required this.item,
    required this.onLighten,
    required this.onOpen,
  });

  final SpaceLighten item;
  final Future<void> Function() onLighten;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _tappable(
      onOpen,
      RowShell(
        posterUrl: item.posterUrl,
        lines: [
          _heading(spaceTitleOf(l, item.title, item.seasonNumber)),
          _line(
            l.spaceLightenLine(
              spaceGb(l, item.sizeBytes),
              NumberFormat('0.0', l.localeName).format(item.gbPerHour),
              spaceGb(l, item.excessBytes),
            ),
          ),
        ],
        actions: [
          AdminActionButton(
            label: l.spaceLightenAction,
            icon: LucideIcons.minimize2,
            onPressed: onLighten,
          ),
        ],
      ),
    );
  }
}

/// Un torrent della pulizia: "Togli", o la data fino a cui resta in seed.
class SpaceTorrentRow extends StatelessWidget {
  const SpaceTorrentRow({
    super.key,
    required this.torrent,
    required this.onRemove,
  });

  final SpaceTorrent torrent;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = torrent;
    final until = t.expectedAt;
    return RowShell(
      posterUrl: null,
      lines: [
        _heading(t.name),
        _line(
          l.spaceTorrentMeta(
            t.tracker,
            spaceGb(l, t.sizeBytes),
            NumberFormat('0.0#', l.localeName).format(t.ratio),
            l.spaceDays(t.seedingDays.floor()),
          ),
        ),
        if (!t.canRemoveNow)
          _line(
            until == null
                ? l.spaceAfterSeed
                : l.spaceSeedUntil(spaceDate(l, until)),
            _gold,
          ),
      ],
      actions: [
        if (t.canRemoveNow)
          AdminActionButton(
            label: l.spaceRemove,
            icon: LucideIcons.trash2,
            onPressed: onRemove,
          ),
      ],
    );
  }
}

/// Un file orfano o un doppione.
class SpaceFileRow extends StatelessWidget {
  const SpaceFileRow({super.key, required this.file, required this.onDelete});

  final SpaceFile file;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return RowShell(
      posterUrl: null,
      lines: [
        _heading(file.path),
        _line(spaceGb(l, file.sizeBytes), _small),
        if (file.linked) _line(l.spaceLinkedNote, _gold),
      ],
      actions: [
        // Con altri collegamenti non si libera nulla (e il plugin rifiuta).
        if (!file.linked)
          AdminActionButton(
            label: l.spaceDeleteFile,
            icon: LucideIcons.trash2,
            onPressed: onDelete,
          ),
      ],
    );
  }
}

/// Un torrent che aspetta la fine del seed.
class SpacePendingRow extends StatelessWidget {
  const SpacePendingRow({
    super.key,
    required this.pending,
    required this.onDrop,
  });

  final SpacePending pending;
  final Future<void> Function() onDrop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = pending;
    final at = p.expectedAt;
    return RowShell(
      posterUrl: null,
      lines: [
        _heading(p.name),
        _line(
          at == null
              ? p.title
              : l.spacePendingExpected(p.title, spaceDate(l, at)),
        ),
      ],
      actions: [
        AdminActionButton(
          label: l.spaceStopWaiting,
          icon: LucideIcons.x,
          onPressed: onDrop,
        ),
      ],
    );
  }
}

/// Un titolo tenuto.
class SpaceKeptRow extends StatelessWidget {
  const SpaceKeptRow({super.key, required this.kept, required this.onUnkeep});

  final SpaceKept kept;
  final Future<void> Function() onUnkeep;

  @override
  Widget build(BuildContext context) => RowShell(
    posterUrl: null,
    lines: [_heading(kept.title)],
    actions: [
      AdminActionButton(
        label: AppLocalizations.of(context).spaceRemove,
        icon: LucideIcons.x,
        onPressed: onUnkeep,
      ),
    ],
  );
}

String spaceOperationState(AppLocalizations l, String state) => switch (state) {
  'Queued' => l.spaceOpQueued,
  'Running' => l.spaceOpRunning,
  'Done' => l.spaceOpDone,
  'Failed' => l.spaceOpFailed,
  _ => state,
};

/// Un'operazione recente: titolo, stato, quando e GB. [onOpen] riapre il
/// riquadro (Task 5).
class SpaceOperationRow extends StatelessWidget {
  const SpaceOperationRow({
    super.key,
    required this.operation,
    required this.now,
    this.onOpen,
  });

  final SpaceOperation operation;
  final DateTime now;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final o = operation;
    final before = o.quotaBeforeBytes;
    final after = o.quotaAfterBytes;
    final freed = before != null && after != null
        ? before - after
        : o.estimatedFreedBytes;
    return _tappable(
      onOpen,
      RowShell(
        posterUrl: null,
        lines: [
          _heading(o.title),
          _line(
            l.spaceOpLine(
              spaceOperationState(l, o.state),
              adminTimeLabel(o.startedAt, now, l),
            ),
          ),
          _line(spaceGb(l, freed), _small),
        ],
        actions: const [],
      ),
    );
  }
}
