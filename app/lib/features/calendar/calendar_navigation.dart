import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

final _monthPattern = RegExp(r'^(\d{4})-(\d{2})$');

/// Il mese dell'indirizzo (`?month=2026-10`); null se manca o non è valido.
DateTime? parseCalendarMonth(String? raw) {
  final match = _monthPattern.firstMatch(raw ?? '');
  if (match == null) return null;
  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12) return null;
  return DateTime(int.parse(match.group(1)!), month);
}

String calendarRoute(DateTime month) =>
    '/calendar?month=${month.year.toString().padLeft(4, '0')}-'
    '${month.month.toString().padLeft(2, '0')}';

void openCalendarMonth(BuildContext context, DateTime month) =>
    context.go(calendarRoute(month));

/// Le due viste del calendario (spec §4.7).
enum CalendarView { month, week }

/// La vista dell'indirizzo: `view=week` vince, poi un `month` valido; null =
/// la vista di partenza secondo lo schermo.
CalendarView? parseCalendarView(Map<String, String> query) {
  if (query['view'] == 'week') return CalendarView.week;
  if (parseCalendarMonth(query['month']) != null) return CalendarView.month;
  return null;
}

const calendarWeekRoute = '/calendar?view=week';

void openCalendarWeek(BuildContext context) => context.go(calendarWeekRoute);
