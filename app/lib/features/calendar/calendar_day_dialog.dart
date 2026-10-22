import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_image.dart';
import 'calendar_logic.dart';

/// Locandina di una riga dell'elenco del giorno.
const _posterWidth = 34.0;
const _posterHeight = 51.0;

/// L'elenco delle uscite di un giorno: una riga per film e per episodio
/// (o blocco di episodi). Un clic chiude la finestra e apre la voce.
Future<void> showCalendarDay(
  BuildContext context, {
  required DateTime day,
  required List<CalendarEntry> entries,
  required void Function(CalendarEntry entry) onOpenEntry,
  required bool Function(CalendarEntry entry) canOpen,
}) {
  final l = AppLocalizations.of(context);
  final title = calendarDayTitle(day, l);
  // Un secondo clic veloce chiuderebbe anche la pagina sotto.
  var closing = false;
  return showWfDialog<void>(
    context,
    semanticLabel: title,
    builder: (context) {
      final time = DateFormat.Hm(l.localeName);
      void open(CalendarEntry entry) {
        if (closing) return;
        closing = true;
        Navigator.of(context).pop();
        onOpenEntry(entry);
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: WfText.display(24)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final entry in entries)
                    if (entry.kind == CalendarEntryKind.movie)
                      _DayRow(
                        entry: entry,
                        subtitle: l.calendarMovieDigital,
                        onServer: entry.onServer,
                        onTap: canOpen(entry) ? () => open(entry) : null,
                      )
                    else
                      for (final e in entry.episodes)
                        _DayRow(
                          entry: entry,
                          subtitle: [
                            episodeCode(
                              e.seasonNumber,
                              e.episodeNumber,
                              last: e.lastEpisodeNumber,
                            ),
                            ?e.episodeTitle,
                          ].join(' · '),
                          time: time.format(e.airDate.toLocal()),
                          onServer: e.onServer,
                          onTap: canOpen(entry) ? () => open(entry) : null,
                        ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.entry,
    required this.subtitle,
    required this.onServer,
    required this.onTap,
    this.time,
  });

  final CalendarEntry entry;
  final String subtitle;
  final String? time;
  final bool onServer;

  /// Null: la voce non porta da nessuna parte (spec §7.4, niente clic).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final poster = entry.posterUrl;
    const muted = TextStyle(fontSize: 13, color: WfColors.creamMuted);
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
                width: _posterWidth,
                height: _posterHeight,
                child: WfImage(
                  image: poster == null ? null : ImageRef(poster),
                  fallbackIcon: entry.kind == CalendarEntryKind.movie
                      ? LucideIcons.film
                      : LucideIcons.tv,
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
                if (time case final t?) Text(t, style: muted),
                if (onServer)
                  Text(
                    l.calendarOnServer,
                    style: const TextStyle(
                      fontSize: 12,
                      color: WfColors.online,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
