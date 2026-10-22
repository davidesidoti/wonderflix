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
import '../../ui/states.dart';
import '../admin/admin_providers.dart';
import '../requests/requests_providers.dart';
import 'calendar_day_dialog.dart';
import 'calendar_logic.dart';
import 'calendar_month_grid.dart';
import 'calendar_navigation.dart';
import 'calendar_providers.dart';

/// La pagina Calendario: la griglia di un mese con le uscite di serie e
/// film. Il mese sta nell'indirizzo (`?month=`), e la rotta rifà la pagina
/// a ogni indirizzo nuovo (decisione 10).
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key, this.month});

  /// Il mese dell'indirizzo; null = il mese di oggi.
  final DateTime? month;

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
    final page = ref.watch(calendarPageProvider(shown));
    void retry() => ref.invalidate(calendarPageProvider(shown));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Text(l.navCalendar.toUpperCase(), style: WfText.display(40)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              IconButton(
                key: const Key('calendar-previous'),
                tooltip: l.calendarPreviousMonth,
                icon: const Icon(LucideIcons.chevronLeft),
                onPressed: () => openCalendarMonth(
                  context,
                  DateTime(shown.year, shown.month - 1),
                ),
              ),
              SizedBox(
                // Larghezza fissa: le frecce non si spostano tra i mesi.
                width: 220,
                child: Text(
                  calendarMonthTitle(shown, l),
                  textAlign: TextAlign.center,
                  style: WfText.display(28),
                ),
              ),
              IconButton(
                key: const Key('calendar-next'),
                tooltip: l.calendarNextMonth,
                icon: const Icon(LucideIcons.chevronRight),
                onPressed: () => openCalendarMonth(
                  context,
                  DateTime(shown.year, shown.month + 1),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                key: const Key('calendar-today'),
                onPressed: shown == thisMonth
                    ? null
                    : () => openCalendarMonth(context, thisMonth),
                child: Text(l.calendarToday),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: page.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(error: error, onRetry: retry),
            data: (data) => _CalendarBody(
              month: shown,
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

class _CalendarBody extends ConsumerWidget {
  const _CalendarBody({
    required this.month,
    required this.today,
    required this.page,
    required this.onRetry,
  });

  final DateTime month;
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
    // Con un servizio in errore il mese non si sa se è vuoto.
    final emptyMonth =
        failing == 0 &&
        !entries.keys.any(
          (d) => d.year == month.year && d.month == month.month,
        );

    String? route(CalendarEntry entry) =>
        calendarEntryRoute(entry, canRequest: canRequest);
    bool canOpen(CalendarEntry entry) => route(entry) != null;
    void openEntry(CalendarEntry entry) {
      if (route(entry) case final r?) unawaited(context.push(r));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (error, text) in [
            (page.seriesError, l.calendarSeriesUnavailable),
            (page.moviesError, l.calendarMoviesUnavailable),
          ])
            if (_failing(error))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
          Expanded(
            child: CalendarMonthGrid(
              month: month,
              today: today,
              entries: entries,
              onOpenDay: (day) {
                final list = entries[day];
                if (list == null || list.isEmpty) return;
                unawaited(
                  showCalendarDay(
                    context,
                    day: day,
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
          if (emptyMonth)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                l.calendarEmpty,
                style: const TextStyle(color: WfColors.creamMuted),
              ),
            ),
        ],
      ),
    );
  }
}
