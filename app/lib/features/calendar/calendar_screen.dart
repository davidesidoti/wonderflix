import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/home_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/states.dart';
import '../admin/admin_providers.dart';
import '../requests/requests_providers.dart';
import 'calendar_day_dialog.dart';
import 'calendar_logic.dart';
import 'calendar_month_grid.dart';
import 'calendar_navigation.dart';
import 'calendar_providers.dart';
import 'calendar_release_row.dart';
import 'calendar_week_view.dart';

/// La pagina Calendario: la griglia di un mese o i prossimi 7 giorni, con
/// le uscite di serie e film. Mese e vista stanno nell'indirizzo (`?month=`,
/// `?view=week`), e la rotta rifà la pagina a ogni indirizzo nuovo
/// (decisione 10).
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key, this.month, this.view});

  /// Il mese dell'indirizzo; null = il mese di oggi.
  final DateTime? month;

  /// La vista dell'indirizzo; null = 7 giorni nello stretto, Mese altrove.
  final CalendarView? view;

  /// Dove va la pagina quando il calendario sparisce: la Home.
  static const _homeRoute = '/home';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Calendario tolto dal plugin mentre si guarda la pagina: come per le
    // Richieste si torna alla Home, senza mostrare l'errore.
    if (ref.watch(calendarGoneProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(_homeRoute);
      });
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final now = clock.now();
    final thisMonth = calendarMonthOf(now);
    final shown = month ?? thisMonth;
    final compact = FormFactor.of(context).compact;
    final week =
        (view ?? (compact ? CalendarView.week : CalendarView.month)) ==
        CalendarView.week;
    final page = week
        ? ref.watch(calendarWeekProvider)
        : ref.watch(calendarPageProvider(shown));
    void retry() => week
        ? ref.invalidate(calendarWeekProvider)
        : ref.invalidate(calendarPageProvider(shown));

    final monthTitle = Text(
      calendarMonthTitle(shown, l),
      textAlign: TextAlign.center,
      style: WfText.display(28),
    );
    final monthNav = [
      IconButton(
        key: const Key('calendar-previous'),
        tooltip: l.calendarPreviousMonth,
        icon: const Icon(LucideIcons.chevronLeft),
        onPressed: () =>
            openCalendarMonth(context, DateTime(shown.year, shown.month - 1)),
      ),
      // Larghezza fissa: le frecce non si spostano tra i mesi; nello
      // stretto il titolo prende lo spazio che resta.
      if (compact)
        Expanded(child: monthTitle)
      else
        SizedBox(width: 220, child: monthTitle),
      IconButton(
        key: const Key('calendar-next'),
        tooltip: l.calendarNextMonth,
        icon: const Icon(LucideIcons.chevronRight),
        onPressed: () =>
            openCalendarMonth(context, DateTime(shown.year, shown.month + 1)),
      ),
      SizedBox(width: compact ? 4 : 12),
      TextButton(
        key: const Key('calendar-today'),
        style: compact
            ? TextButton.styleFrom(minimumSize: const Size(0, minTouchTarget))
            : null,
        onPressed: shown == thisMonth
            ? null
            : () => openCalendarMonth(context, thisMonth),
        child: Text(l.calendarToday),
      ),
    ];
    final viewButton = SegmentedButton<CalendarView>(
      showSelectedIcon: false,
      style: compact
          ? SegmentedButton.styleFrom(
              minimumSize: const Size(0, minTouchTarget),
            )
          : null,
      segments: [
        ButtonSegment(
          value: CalendarView.month,
          label: Text(
            l.calendarViewMonth,
            key: const Key('calendar-view-month'),
          ),
        ),
        ButtonSegment(
          value: CalendarView.week,
          label: Text(l.calendarViewWeek, key: const Key('calendar-view-week')),
        ),
      ],
      selected: {week ? CalendarView.week : CalendarView.month},
      onSelectionChanged: (s) => s.first == CalendarView.week
          ? openCalendarWeek(context)
          : openCalendarMonth(context, thisMonth),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 32,
            16,
            compact ? 16 : 32,
            12,
          ),
          child: Text(
            l.navCalendar.toUpperCase(),
            style: WfText.display(compact ? 28 : 40),
          ),
        ),
        if (compact) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(width: double.infinity, child: viewButton),
          ),
          if (!week)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(children: monthNav),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 32, 0),
            child: Row(
              children: [
                if (!week) ...monthNav,
                // La legenda si rimpicciolisce invece di sforare (finestre
                // vicine ai 1024 px, testo ingrandito).
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(fit: BoxFit.scaleDown, child: _Legend()),
                  ),
                ),
                const SizedBox(width: 20),
                viewButton,
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: page.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(error: error, onRetry: retry),
            data: (data) => _CalendarBody(
              month: week ? null : shown,
              today: dayKey(now),
              page: data,
              onRetry: retry,
            ),
          ),
        ),
      ],
    );
  }
}

/// `▍Film ▍Serie ○ Non ancora arrivato`, fuori dallo stretto (spec §4.3).
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget bar(Color color) => Container(
      width: 3,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    final ring = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: WfColors.gold, width: 1.5),
      ),
    );
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 12, color: WfColors.creamMuted),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          for (final (mark, text) in [
            (bar(WfColors.gold), l.requestsKindMovie),
            (bar(WfColors.calendarSeriesMark), l.requestsKindSeries),
            (ring, l.calendarNotArrived),
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [mark, const SizedBox(width: 6), Text(text)],
            ),
        ],
      ),
    );
  }
}

class _CalendarBody extends ConsumerWidget {
  const _CalendarBody({
    required this.month,
    required this.today,
    required this.page,
    required this.onRetry,
  });

  /// Null: la vista 7 giorni.
  final DateTime? month;
  final DateTime today;
  final CalendarPage page;
  final VoidCallback onRetry;

  /// In errore solo chiave rifiutata e servizio irraggiungibile: un
  /// servizio non configurato è spento, e non se ne parla (decisione 3).
  static bool _failing(UpcomingError? error) =>
      error == UpcomingError.unauthorized || error == UpcomingError.unreachable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final errors = [page.seriesError, page.moviesError];
    final on = errors.where((e) => e != UpcomingError.notConfigured).length;
    final failing = errors.where(_failing).length;
    if (failing > 0 && failing == on) {
      return ErrorView(error: const ServerErrorException(null), onRetry: onRetry);
    }
    final admin = ref.watch(isAdminProvider);
    // Il motivo per l'admin: gli stessi testi della card di prova.
    String line(String text, UpcomingError error) => !admin
        ? text
        : '$text · ${error == UpcomingError.unauthorized ? l.adminArrUnauthorized : l.adminArrUnreachable}';
    final canRequest = ref.watch(requestsAvailableProvider);
    final entries = entriesByDay(page);

    String? route(CalendarEntry entry) =>
        calendarEntryRoute(entry, canRequest: canRequest);
    bool canOpen(CalendarEntry entry) => route(entry) != null;
    void openEntry(CalendarEntry entry) {
      if (route(entry) case final r?) unawaited(context.push(r));
    }

    final compact = FormFactor.of(context).compact;
    final side = compact ? 16.0 : 32.0;
    final month = this.month;
    final Widget content;
    if (month == null) {
      // La settimana ha già i suoi margini e scorre da sola.
      content = CalendarWeekView(
        today: today,
        now: clock.now(),
        entries: entries,
        // Con un servizio in errore la settimana non si sa se è vuota.
        knownEmpty:
            failing == 0 &&
            calendarWeekDays(today).every((d) => entries[d]?.isEmpty ?? true),
        onOpenEntry: openEntry,
        canOpen: canOpen,
        compact: compact,
      );
    } else {
      // Con un servizio in errore il mese non si sa se è vuoto.
      final emptyMonth =
          failing == 0 &&
          !entries.keys.any(
            (d) => d.year == month.year && d.month == month.month,
          );
      content = compact
          ? _CompactMonth(
              month: month,
              today: today,
              entries: entries,
              emptyMonth: emptyMonth,
              onOpenEntry: openEntry,
              canOpen: canOpen,
            )
          : Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CalendarMonthGrid(
                      month: month,
                      today: today,
                      now: clock.now(),
                      entries: entries,
                      onOpenDay: (day) {
                        final list = entries[day];
                        if (list == null || list.isEmpty) return;
                        unawaited(
                          showCalendarDay(
                            context,
                            day: day,
                            today: today,
                            now: clock.now(),
                            entries: list,
                            onOpenEntry: openEntry,
                            canOpen: canOpen,
                          ),
                        );
                      },
                      onOpenEntry: openEntry,
                      canOpen: canOpen,
                    ),
                  ),
                  if (emptyMonth) const _EmptyMonth(),
                ],
              ),
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (error, text) in [
          (page.seriesError, l.calendarSeriesUnavailable),
          (page.moviesError, l.calendarMoviesUnavailable),
        ])
          if (_failing(error))
            Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 8),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.circleAlert,
                    size: 14,
                    color: WfColors.gold,
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Text(line(text, error!))),
                ],
              ),
            ),
        Expanded(child: content),
      ],
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      AppLocalizations.of(context).calendarEmpty,
      style: const TextStyle(color: WfColors.creamMuted),
    ),
  );
}

/// Il mese nello stretto: la griglia in modo selezione e sotto le uscite
/// del giorno scelto, in una sola colonna che scorre (spec §4.9).
class _CompactMonth extends StatefulWidget {
  const _CompactMonth({
    required this.month,
    required this.today,
    required this.entries,
    required this.emptyMonth,
    required this.onOpenEntry,
    required this.canOpen,
  });

  final DateTime month;
  final DateTime today;
  final Map<DateTime, List<CalendarEntry>> entries;
  final bool emptyMonth;
  final void Function(CalendarEntry entry) onOpenEntry;
  final bool Function(CalendarEntry entry) canOpen;

  @override
  State<_CompactMonth> createState() => _CompactMonthState();
}

class _CompactMonthState extends State<_CompactMonth> {
  // Oggi se è nella griglia, se no il primo del mese.
  late DateTime _selected = gridDaysOf(widget.month).contains(widget.today)
      ? widget.today
      : DateTime(widget.month.year, widget.month.month);

  @override
  Widget build(BuildContext context) {
    final now = clock.now();
    // Sempre lo stesso albero: cambiare i widget sopra la colonna ne
    // azzererebbe lo scorrimento.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CalendarMonthGrid(
            month: widget.month,
            today: widget.today,
            now: now,
            entries: widget.entries,
            onOpenDay: (_) {},
            onOpenEntry: widget.onOpenEntry,
            canOpen: widget.canOpen,
            selectedDay: _selected,
            onSelectDay: (day) => setState(() => _selected = day),
          ),
          const SizedBox(height: 16),
          CalendarDayList(
            day: _selected,
            today: widget.today,
            now: now,
            entries: widget.entries[_selected] ?? const [],
            onOpenEntry: widget.onOpenEntry,
            canOpen: widget.canOpen,
            compactStatus: true,
            // Un mese vuoto lo dice già _EmptyMonth.
            showEmpty: !widget.emptyMonth,
          ),
          if (widget.emptyMonth) const _EmptyMonth(),
        ],
      ),
    );
  }
}
