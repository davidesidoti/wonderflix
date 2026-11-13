import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'calendar_logic.dart';
import 'calendar_release_row.dart';

/// "Prossimi 7 giorni": un elenco per giorno, da oggi (spec §4.8).
class CalendarWeekView extends StatelessWidget {
  const CalendarWeekView({
    super.key,
    required this.today,
    required this.now,
    required this.entries,
    required this.knownEmpty,
    required this.onOpenEntry,
    required this.canOpen,
    this.compact = false,
  });

  final DateTime today;
  final DateTime now;
  final Map<DateTime, List<CalendarEntry>> entries;

  /// Nessuna voce nei 7 giorni e nessun servizio in errore: si dice una volta
  /// sola invece di "Nessuna uscita" su ogni giorno.
  final bool knownEmpty;
  final void Function(CalendarEntry entry) onOpenEntry;
  final bool Function(CalendarEntry entry) canOpen;

  /// Stretto: locandine piccole e solo il segno di stato.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final side = compact ? 16.0 : 32.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(side, 8, side, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: compact ? double.infinity : 720,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final day in calendarWeekDays(today))
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: CalendarDayList(
                    day: day,
                    today: today,
                    now: now,
                    entries: entries[day] ?? const [],
                    onOpenEntry: onOpenEntry,
                    canOpen: canOpen,
                    large: !compact,
                    compactStatus: compact,
                    showEmpty: !knownEmpty,
                  ),
                ),
              if (knownEmpty)
                Text(
                  AppLocalizations.of(context).calendarWeekEmpty,
                  style: const TextStyle(color: WfColors.creamMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
