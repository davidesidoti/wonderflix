import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/requests/remote_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import 'calendar_logic.dart';

/// Un giorno: l'intestazione e le sue uscite in ordine di ora (spec §4.8).
class CalendarDayList extends StatelessWidget {
  const CalendarDayList({
    super.key,
    required this.day,
    required this.today,
    required this.now,
    required this.entries,
    required this.onOpenEntry,
    required this.canOpen,
    this.large = false,
    this.compactStatus = false,
    this.showEmpty = true,
  });

  final DateTime day;
  final DateTime today;
  final DateTime now;
  final List<CalendarEntry> entries;
  final void Function(CalendarEntry entry) onOpenEntry;
  final bool Function(CalendarEntry entry) canOpen;
  final bool large;
  final bool compactStatus;

  /// Senza voci scrive "Nessuna uscita".
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final date = DateFormat.MMMMEEEEd(l.localeName).format(day);
    final isToday = day == today;
    final isTomorrow = day == DateTime(today.year, today.month, today.day + 1);
    final name = isToday
        ? l.calendarToday
        : isTomorrow
        ? l.calendarTomorrow
        : calendarDayTitle(day, l);
    final rows = calendarRows(entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            key: Key(
              'calendar-heading-${DateFormat('yyyy-MM-dd').format(day)}',
            ),
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WfText.display(
                    24,
                    color: isToday ? WfColors.gold : WfColors.cream,
                  ),
                ),
              ),
              if (isToday || isTomorrow) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: WfColors.creamMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (rows.isEmpty && showEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(
              l.calendarNoReleases,
              style: const TextStyle(color: WfColors.creamMuted),
            ),
          ),
        for (final row in rows)
          CalendarReleaseRow(
            row: row,
            day: day,
            now: now,
            large: large,
            compactStatus: compactStatus,
            onTap: canOpen(row.entry) ? () => onOpenEntry(row.entry) : null,
          ),
      ],
    );
  }
}

/// Una riga d'uscita: un film, o un episodio (o blocco) di una serie.
class CalendarReleaseRow extends StatelessWidget {
  const CalendarReleaseRow({
    super.key,
    required this.row,
    required this.day,
    required this.now,
    required this.onTap,
    this.large = false,
    this.compactStatus = false,
  });

  final CalendarRow row;
  final DateTime day;
  final DateTime now;

  /// Null: la voce non porta da nessuna parte (spec S §7.4, niente clic).
  final VoidCallback? onTap;

  /// Locandina 40×60 invece di 34×51.
  final bool large;

  /// Solo il segno, senza testo (il testo resta nella semantica).
  final bool compactStatus;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = row.entry;
    final episode = row.episode;
    final isMovie = episode == null;
    final state = calendarRowState(row, day: day, now: now);
    final poster = entry.posterUrl;
    const muted = TextStyle(fontSize: 13, color: WfColors.creamMuted);
    final subtitle = episode == null
        ? l.calendarMovieDigital
        : [
            episodeCode(
              episode.seasonNumber,
              episode.episodeNumber,
              last: episode.lastEpisodeNumber,
            ),
            ?episodeTitleOrNull(episode.episodeTitle),
          ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: large ? 40 : 34,
                height: large ? 60 : 51,
                child: WfImage(
                  image: poster == null ? null : RemoteImages.poster(poster),
                  fallbackIcon: isMovie ? LucideIcons.film : LucideIcons.tv,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (episode != null)
                  Text(
                    DateFormat.Hm(
                      l.localeName,
                    ).format(episode.airDate.toLocal()),
                    style: muted.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                _Status(state: state, compact: compactStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state, required this.compact});

  final CalendarEntryState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (text, color) = switch (state) {
      CalendarEntryState.arrived => (l.calendarOnServer, WfColors.online),
      CalendarEntryState.missing => (l.calendarNotArrived, WfColors.gold),
      CalendarEntryState.upcoming => (null, WfColors.gold),
    };
    if (text == null) return const SizedBox.shrink();
    final mark = state == CalendarEntryState.arrived
        ? Icon(LucideIcons.check, size: 14, color: color)
        : Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
          );
    if (compact) return Semantics(label: text, child: mark);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
