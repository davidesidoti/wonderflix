import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'calendar_logic.dart';

/// La griglia del mese: sette colonne dal lunedì, sei righe.
class CalendarMonthGrid extends StatefulWidget {
  const CalendarMonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.entries,
    required this.onOpenDay,
    required this.onOpenEntry,
  });

  final DateTime month;
  final DateTime today;
  final Map<DateTime, List<CalendarEntry>> entries;
  final void Function(DateTime day) onOpenDay;
  final void Function(CalendarEntry entry) onOpenEntry;

  /// Sotto questa larghezza la casella mostra solo numero e puntini.
  static const compactCellWidth = 96.0;

  /// Altezza della riga col numero del giorno.
  static const dayRowHeight = 22.0;

  /// Altezza di una voce, spazio sopra compreso.
  static const entryHeight = 20.0;

  /// Voci che una casella mostra comunque, anche se bassa.
  static const minEntries = 2;

  @override
  State<CalendarMonthGrid> createState() => _CalendarMonthGridState();
}

/// Spazio tra le caselle.
const _gap = 4.0;

/// Altezza della riga con i nomi dei giorni.
const _headerHeight = 24.0;

/// Puntini al massimo in una casella stretta.
const _maxDots = 4;

/// Un lunedì qualunque, per i nomi dei giorni.
final _aMonday = DateTime(2026, 9, 28);

String _dayId(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

class _CalendarMonthGridState extends State<CalendarMonthGrid> {
  late final List<DateTime> _days = gridDaysOf(widget.month);
  late int _selected = _startIndex();
  bool _focused = false;

  // Da oggi, o dal primo del mese se oggi non è nella griglia.
  int _startIndex() {
    final today = _days.indexOf(dayKey(widget.today));
    return today >= 0
        ? today
        : _days.indexOf(DateTime(widget.month.year, widget.month.month));
  }

  List<CalendarEntry> _entriesOf(DateTime day) =>
      widget.entries[day] ?? const [];

  void _openDay(DateTime day) {
    // Un giorno senza voci non ha niente da elencare.
    if (_entriesOf(day).isNotEmpty) widget.onOpenDay(day);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _openDay(_days[_selected]);
      return KeyEventResult.handled;
    }
    final step = switch (key) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp => -7,
      LogicalKeyboardKey.arrowDown => 7,
      _ => null,
    };
    if (step == null) return KeyEventResult.ignored;
    final next = _selected + step;
    if (next >= 0 && next < _days.length) setState(() => _selected = next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final weekday = DateFormat.E(l.localeName);
    return Focus(
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = (constraints.maxWidth - 6 * _gap) / 7;
          final cellHeight =
              (constraints.maxHeight - _headerHeight - 5 * _gap) / 6;
          final compact = cellWidth < CalendarMonthGrid.compactCellWidth;
          final rows = max(
            CalendarMonthGrid.minEntries,
            ((cellHeight - CalendarMonthGrid.dayRowHeight) /
                    CalendarMonthGrid.entryHeight)
                .floor(),
          );
          Widget week(int w) => Expanded(
            child: Row(
              children: [
                for (var d = 0; d < 7; d++) ...[
                  if (d > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: _cell(l, w * 7 + d, compact: compact, rows: rows),
                  ),
                ],
              ],
            ),
          );
          return Column(
            children: [
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    for (var d = 0; d < 7; d++) ...[
                      if (d > 0) const SizedBox(width: _gap),
                      Expanded(
                        child: Text(
                          weekday.format(
                            DateTime(
                              _aMonday.year,
                              _aMonday.month,
                              _aMonday.day + d,
                            ),
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WfColors.creamMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (var w = 0; w < 6; w++) ...[
                if (w > 0) const SizedBox(height: _gap),
                week(w),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _cell(
    AppLocalizations l,
    int index, {
    required bool compact,
    required int rows,
  }) {
    final day = _days[index];
    final id = _dayId(day);
    final entries = _entriesOf(day);
    final inMonth = day.month == widget.month.month;
    final border = _focused && index == _selected
        ? Border.all(color: WfColors.cream, width: 2)
        : day == dayKey(widget.today)
        ? Border.all(color: WfColors.gold)
        : null;
    final title = calendarDayTitle(day, l);
    // Con troppe voci l'ultima riga diventa "+n".
    final shown = entries.length > rows ? rows - 1 : entries.length;
    return Semantics(
      key: Key('calendar-day-$id'),
      container: true,
      explicitChildNodes: true,
      button: true,
      label: entries.isEmpty
          ? title
          : l.calendarDayReleases(title, entries.length),
      child: MouseRegion(
        cursor: entries.isEmpty ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDay(day),
          child: Container(
            decoration: BoxDecoration(
              color: WfColors.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
              border: border,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ClipRect(
              // Una casella più bassa delle voci minime taglia invece di sforare.
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: CalendarMonthGrid.dayRowHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ExcludeSemantics(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 12,
                              color: inMonth
                                  ? WfColors.cream
                                  : WfColors.creamMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (compact)
                      Wrap(
                        spacing: 4,
                        children: [
                          for (var i = 0; i < min(entries.length, _maxDots); i++)
                            _Dot(
                              key: Key('calendar-dot-$id-$i'),
                              color: entries[i].kind == CalendarEntryKind.movie
                                  ? WfColors.gold
                                  : WfColors.cream,
                            ),
                        ],
                      )
                    else ...[
                      for (var i = 0; i < shown; i++)
                        _EntryChip(
                          key: Key('calendar-entry-$id-$i'),
                          entry: entries[i],
                          serverDotKey: Key('calendar-entry-$id-$i-server'),
                          onTap: () => widget.onOpenEntry(entries[i]),
                        ),
                      if (shown < entries.length)
                        SizedBox(
                          height: CalendarMonthGrid.entryHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ExcludeSemantics(
                              child: Text(
                                l.calendarMore(entries.length - shown),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: WfColors.creamMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryChip extends StatelessWidget {
  const _EntryChip({
    super.key,
    required this.entry,
    required this.serverDotKey,
    required this.onTap,
  });

  final CalendarEntry entry;
  final Key serverDotKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final movie = entry.kind == CalendarEntryKind.movie;
    final label = calendarEntryLabel(entry, l);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [
        movie ? l.requestsKindMovie : l.requestsKindSeries,
        label,
        if (entry.onServer) l.calendarAlreadyOnServer,
      ].join(', '),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: CalendarMonthGrid.entryHeight - 2,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: movie ? WfColors.calendarMovie : WfColors.calendarSeries,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                Icon(
                  movie ? LucideIcons.film : LucideIcons.tv,
                  size: 12,
                  color: WfColors.creamMuted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(fontSize: 11, color: WfColors.cream),
                  ),
                ),
                if (entry.onServer) ...[
                  const SizedBox(width: 4),
                  _Dot(key: serverDotKey, color: WfColors.online),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
