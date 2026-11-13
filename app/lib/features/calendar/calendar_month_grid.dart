import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import 'calendar_logic.dart';

/// La griglia del mese: sette colonne dal lunedì, sei righe.
///
/// Con [onSelectDay] la griglia è in modo selezione (lo stretto): caselle
/// sempre a puntini, alte [selectionCellHeight], altezza fissa, e il tocco
/// seleziona il giorno invece di aprirlo.
class CalendarMonthGrid extends StatefulWidget {
  const CalendarMonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.now,
    required this.entries,
    required this.onOpenDay,
    required this.onOpenEntry,
    required this.canOpen,
    this.selectedDay,
    this.onSelectDay,
  });

  final DateTime month;
  final DateTime today;

  /// L'istante di adesso: dice cosa è già uscito e le ore di oggi.
  final DateTime now;
  final Map<DateTime, List<CalendarEntry>> entries;
  final void Function(DateTime day) onOpenDay;
  final void Function(CalendarEntry entry) onOpenEntry;

  /// Se la voce porta da qualche parte; se no niente clic (spec §7.4).
  final bool Function(CalendarEntry entry) canOpen;

  /// Il giorno evidenziato, in modo selezione.
  final DateTime? selectedDay;

  /// Se dato, modo selezione: ogni giorno si può selezionare.
  final void Function(DateTime day)? onSelectDay;

  /// Sotto questa larghezza la casella mostra solo numero e puntini.
  static const compactCellWidth = 96.0;

  /// Altezza della riga col numero del giorno.
  static const dayRowHeight = 22.0;

  /// Altezza di una voce, spazio sopra compreso.
  static const entryHeight = 20.0;

  /// Altezza di una casella in modo selezione.
  static const selectionCellHeight = 48.0;

  /// Voci che una casella mostra comunque, anche se bassa: una, che con
  /// più voci diventa "+n altre" (alla finestra minima due non ci stanno).
  static const minEntries = 1;

  @override
  State<CalendarMonthGrid> createState() => _CalendarMonthGridState();
}

/// Spazio tra le caselle.
const _gap = 4.0;

/// Altezza della riga con i nomi dei giorni.
const _headerHeight = 24.0;

/// Puntini al massimo in una casella stretta.
const _maxDots = 4;

/// Opacità del passato del mese e dei mesi vicini (spec §4.4).
const _pastOpacity = 0.42;
const _outOpacity = 0.30;

const _selectedFill = Color(0xFF2A2418);
const _hoverBorder = Color(0xFF3A3A3A);

/// Un lunedì qualunque, per i nomi dei giorni.
final _aMonday = DateTime(2026, 9, 28);

String _dayId(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

Widget _dim(double opacity, Widget child) =>
    opacity < 1 ? Opacity(opacity: opacity, child: child) : child;

class _CalendarMonthGridState extends State<CalendarMonthGrid> {
  // Fissi: la pagina rifà la griglia a ogni mese (ValueKey, decisione 10).
  late final List<DateTime> _days = gridDaysOf(widget.month);
  late int _selected = _startIndex();
  bool _focused = false;
  int? _hovered;

  // Dal giorno selezionato, se no da oggi, o dal primo del mese se oggi non
  // è nella griglia.
  int _startIndex() {
    if (widget.selectedDay case final day?) {
      final selected = _days.indexOf(dayKey(day));
      if (selected >= 0) return selected;
    }
    final today = _days.indexOf(dayKey(widget.today));
    return today >= 0
        ? today
        : _days.indexOf(DateTime(widget.month.year, widget.month.month));
  }

  List<CalendarEntry> _entriesOf(DateTime day) =>
      widget.entries[day] ?? const [];

  void _activate(DateTime day) {
    final select = widget.onSelectDay;
    if (select != null) {
      // Anche la tastiera riparte dal giorno scelto col tocco.
      setState(() => _selected = _days.indexOf(day));
      select(day);
    } else if (_entriesOf(day).isNotEmpty) {
      // Un giorno senza voci non ha niente da elencare.
      widget.onOpenDay(day);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _activate(_days[_selected]);
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
    final selection = widget.onSelectDay != null;
    return Focus(
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Nello stretto le caselle si toccano col dito: se non ci stanno
          // alte almeno [minTouchTarget] la griglia scorre in verticale.
          final minHeight = FormFactor.of(context).compact
              ? _headerHeight + 5 * _gap + 6 * minTouchTarget
              : 0.0;
          // In modo selezione l'altezza è fissa: scorre la pagina, non la
          // griglia.
          final gridHeight = selection
              ? _headerHeight +
                    6 * CalendarMonthGrid.selectionCellHeight +
                    5 * _gap
              : max(constraints.maxHeight, minHeight);
          final scrolls = !selection && gridHeight > constraints.maxHeight;
          final cellWidth = (constraints.maxWidth - 6 * _gap) / 7;
          final cellHeight = (gridHeight - _headerHeight - 5 * _gap) / 6;
          final compact =
              selection || cellWidth < CalendarMonthGrid.compactCellWidth;
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
          final grid = Column(
            children: [
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    for (var d = 0; d < 7; d++) ...[
                      if (d > 0) const SizedBox(width: _gap),
                      Expanded(
                        child: Padding(
                          // Come il numero del giorno nella casella; nello
                          // stretto le colonne sono troppo strette.
                          padding: EdgeInsets.only(left: compact ? 0 : 8),
                          child: Text(
                            weekday.format(
                              DateTime(
                                _aMonday.year,
                                _aMonday.month,
                                _aMonday.day + d,
                              ),
                            ),
                            textAlign: compact
                                ? TextAlign.center
                                : TextAlign.left,
                            style: TextStyle(
                              fontSize: 12,
                              color: d >= 5
                                  ? WfColors.cream.withValues(alpha: 0.45)
                                  : WfColors.creamMuted,
                            ),
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
          if (selection) {
            // Sotto un genitore a misura obbligata la griglia resta alta
            // [gridHeight]: la SizedBox sta dentro un Align.
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(height: gridHeight, child: grid),
            );
          }
          if (!scrolls) return grid;
          return SingleChildScrollView(
            child: SizedBox(height: gridHeight, child: grid),
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
    final selection = widget.onSelectDay != null;
    final today = dayKey(widget.today);
    final isToday = day == today;
    final inMonth = day.month == widget.month.month;
    final past = inMonth && day.isBefore(today);
    final selected =
        widget.selectedDay != null && dayKey(widget.selectedDay!) == day;
    final states = [
      for (final e in entries)
        calendarEntryState(e, day: day, now: widget.now),
    ];
    // Il passato e i mesi vicini si spengono; una voce che manca no, tranne
    // nei mesi vicini.
    double opacity({bool missing = false}) => !inMonth
        ? _outOpacity
        : past && !missing
        ? _pastOpacity
        : 1;
    final focus = _focused && index == _selected;
    final border = focus
        ? Border.all(color: WfColors.cream, width: 2)
        : isToday
        ? Border.all(color: WfColors.gold, width: 2)
        : _hovered == index && entries.isNotEmpty
        ? Border.all(color: _hoverBorder)
        : Border.all(color: inMonth ? Colors.transparent : WfColors.surface);
    final borderWidth = border.top.width;
    final title = calendarDayTitle(day, l);
    // Con troppe voci l'ultima riga diventa "+n altre".
    final shown = entries.length > rows ? rows - 1 : entries.length;
    final dayNumber = Text(
      '${day.day}',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: compact && isToday ? WfColors.gold : WfColors.cream,
      ),
    );
    final numberRow = SizedBox(
      height: CalendarMonthGrid.dayRowHeight,
      child: Align(
        alignment: compact ? Alignment.center : Alignment.centerLeft,
        child: ExcludeSemantics(
          child: _dim(
            opacity(),
            compact || !isToday
                ? dayNumber
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        constraints: const BoxConstraints(minWidth: 24),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: WfColors.gold,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${day.day}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: WfColors.bg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Flexible: in una casella stretta "Oggi" si accorcia.
                      Flexible(
                        child: Text(
                          l.calendarToday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: WfColors.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    return Semantics(
      key: Key('calendar-day-$id'),
      container: true,
      explicitChildNodes: true,
      button: selection || entries.isNotEmpty,
      selected: selection ? selected : null,
      label: entries.isEmpty
          ? title
          : l.calendarDayReleases(title, entries.length),
      onTap: selection || entries.isNotEmpty ? () => _activate(day) : null,
      child: MouseRegion(
        cursor: selection || entries.isNotEmpty
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = index),
        onExit: (_) {
          if (mounted && _hovered == index) setState(() => _hovered = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _activate(day),
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? _selectedFill
                  : !inMonth
                  ? Colors.transparent
                  : past
                  ? WfColors.surface
                  : WfColors.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
              border: border,
            ),
            // Il bordo più spesso non sposta i contenuti. A puntini il
            // margine è stretto: 4 puntini stanno in riga a 360 px.
            padding: EdgeInsets.symmetric(
              horizontal: (compact ? 4 : 7) - borderWidth,
            ),
            child: ClipRect(
              // Una casella più bassa delle voci minime taglia invece di sforare.
              child: OverflowBox(
                alignment: compact ? Alignment.topCenter : Alignment.topLeft,
                maxHeight: double.infinity,
                child: Column(
                  crossAxisAlignment: compact
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    numberRow,
                    if (compact)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 2,
                        children: [
                          for (var i = 0; i < min(entries.length, _maxDots); i++)
                            _dim(
                              opacity(
                                missing: states[i] == CalendarEntryState.missing,
                              ),
                              _dot(
                                Key('calendar-dot-$id-$i'),
                                entries[i].kind == CalendarEntryKind.movie
                                    ? WfColors.gold
                                    : WfColors.calendarSeriesMark,
                                hollow:
                                    states[i] == CalendarEntryState.missing,
                              ),
                            ),
                        ],
                      )
                    else ...[
                      for (var i = 0; i < shown; i++)
                        _dim(
                          opacity(
                            missing: states[i] == CalendarEntryState.missing,
                          ),
                          _EntryChip(
                            key: Key('calendar-entry-$id-$i'),
                            keyPrefix: 'calendar-entry-$id-$i',
                            entry: entries[i],
                            state: states[i],
                            time: isToday ? _timeOf(entries[i]) : null,
                            showArrival: isToday,
                            onTap: widget.canOpen(entries[i])
                                ? () => widget.onOpenEntry(entries[i])
                                : null,
                          ),
                        ),
                      if (shown < entries.length)
                        _dim(
                          opacity(),
                          SizedBox(
                            height: CalendarMonthGrid.entryHeight,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ExcludeSemantics(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    l.calendarMore(entries.length - shown),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: WfColors.cream.withValues(
                                        alpha: 0.75,
                                      ),
                                      decoration: _hovered == index
                                          ? TextDecoration.underline
                                          : null,
                                      decorationColor: WfColors.cream,
                                    ),
                                  ),
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

  /// L'ora locale del primo episodio non ancora uscito, `null` per un film
  /// o se non ne restano.
  String? _timeOf(CalendarEntry entry) {
    for (final e in entry.episodes) {
      if (e.airDate.isAfter(widget.now)) {
        return DateFormat('HH:mm').format(e.airDate.toLocal());
      }
    }
    return null;
  }
}

class _EntryChip extends StatefulWidget {
  const _EntryChip({
    super.key,
    required this.keyPrefix,
    required this.entry,
    required this.state,
    required this.time,
    required this.showArrival,
    required this.onTap,
  });

  /// Le key dei segni sono `<keyPrefix>-bar`, `-missing`, `-arrived`.
  final String keyPrefix;
  final CalendarEntry entry;
  final CalendarEntryState state;

  /// `HH:mm` da mostrare a destra (solo oggi, solo se ancora da uscire).
  final String? time;

  /// Oggi: ✓ per una voce arrivata.
  final bool showArrival;

  /// Null: la voce non porta da nessuna parte, il tocco va alla casella.
  final VoidCallback? onTap;

  @override
  State<_EntryChip> createState() => _EntryChipState();
}

class _EntryChipState extends State<_EntryChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    final movie = entry.kind == CalendarEntryKind.movie;
    final label = calendarEntryLabel(entry, l);
    final kind = movie ? l.requestsKindMovie : l.requestsKindSeries;
    // "×n" in grigio subito dopo il nome.
    final split = label.length > entry.title.length &&
        label.startsWith(entry.title);
    final tap = widget.onTap;
    final Widget? mark = switch (widget.state) {
      CalendarEntryState.missing => Container(
        key: Key('${widget.keyPrefix}-missing'),
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: WfColors.gold, width: 1.5),
        ),
      ),
      CalendarEntryState.arrived when widget.showArrival => Icon(
        LucideIcons.check,
        key: Key('${widget.keyPrefix}-arrived'),
        size: 12,
        color: WfColors.online,
      ),
      CalendarEntryState.upcoming when widget.time != null => Text(
        widget.time!,
        style: const TextStyle(
          fontSize: 11.5,
          color: WfColors.creamMuted,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      _ => null,
    };
    final chip = Container(
      height: CalendarMonthGrid.entryHeight - 2,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _hovered && tap != null ? WfColors.border : null,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Container(
            key: Key('${widget.keyPrefix}-bar'),
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: movie ? WfColors.gold : WfColors.calendarSeriesMark,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: split ? entry.title : label,
                children: [
                  if (split)
                    TextSpan(
                      text: label.substring(entry.title.length),
                      style: const TextStyle(color: WfColors.creamMuted),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: const TextStyle(fontSize: 12.5, color: WfColors.cream),
            ),
          ),
          if (mark != null) ...[const SizedBox(width: 4), mark],
        ],
      ),
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [
        kind,
        label,
        if (widget.state == CalendarEntryState.arrived)
          l.calendarAlreadyOnServer,
        if (widget.state == CalendarEntryState.missing) l.calendarNotArrived,
      ].join(', '),
      onTap: tap,
      child: Tooltip(
        message: '$kind: $label',
        waitDuration: const Duration(milliseconds: 500),
        child: tap == null
            ? chip
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) {
                  if (mounted) setState(() => _hovered = false);
                },
                child: GestureDetector(onTap: tap, child: chip),
              ),
      ),
    );
  }
}

/// Un puntino: pieno, o un cerchio vuoto oro per una voce che manca.
Widget _dot(Key key, Color color, {required bool hollow}) => Container(
  key: key,
  width: 6,
  height: 6,
  decoration: hollow
      ? BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: WfColors.gold, width: 1.2),
        )
      : BoxDecoration(color: color, shape: BoxShape.circle),
);
