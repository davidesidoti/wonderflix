import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import 'calendar_logic.dart';
import 'calendar_release_row.dart';

/// L'elenco delle uscite di un giorno: una riga per film e per episodio
/// (o blocco di episodi). Un clic chiude la finestra e apre la voce.
Future<void> showCalendarDay(
  BuildContext context, {
  required DateTime day,
  required DateTime today,
  required DateTime now,
  required List<CalendarEntry> entries,
  required void Function(CalendarEntry entry) onOpenEntry,
  required bool Function(CalendarEntry entry) canOpen,
}) {
  final l = AppLocalizations.of(context);
  final title = calendarDayTitle(day, l);
  final pill = day == today
      ? l.calendarToday
      : day == DateTime(today.year, today.month, today.day + 1)
      ? l.calendarTomorrow
      : null;
  final rows = calendarRows(entries);
  final here = rows
      .where(
        (r) =>
            calendarRowState(r, day: day, now: now) ==
            CalendarEntryState.arrived,
      )
      .length;
  final summary = [
    l.calendarDaySummary(rows.length),
    if (here > 0) l.calendarDayOnServer(here),
  ].join(' · ');
  // Un secondo clic veloce chiuderebbe anche la pagina sotto.
  var closing = false;
  return showWfDialog<void>(
    context,
    semanticLabel: title,
    builder: (context) {
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
          Row(
            children: [
              Flexible(child: Text(title, style: WfText.display(24))),
              if (pill != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: WfColors.gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    pill,
                    style: const TextStyle(fontSize: 12, color: WfColors.bg),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: const TextStyle(fontSize: 13, color: WfColors.creamMuted),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final row in rows)
                    CalendarReleaseRow(
                      row: row,
                      day: day,
                      now: now,
                      onTap: canOpen(row.entry) ? () => open(row.entry) : null,
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
