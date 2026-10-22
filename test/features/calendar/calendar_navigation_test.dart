import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/calendar/calendar_navigation.dart';

void main() {
  test('parseCalendarMonth legge solo YYYY-MM con un mese vero', () {
    expect(parseCalendarMonth('2026-10'), DateTime(2026, 10));
    expect(parseCalendarMonth('2026-13'), isNull);
    expect(parseCalendarMonth('2026-00'), isNull);
    expect(parseCalendarMonth('2026-1'), isNull);
    expect(parseCalendarMonth('boh'), isNull);
    expect(parseCalendarMonth(null), isNull);
  });

  test('calendarRoute mette il mese con due cifre', () {
    expect(calendarRoute(DateTime(2026, 3)), '/calendar?month=2026-03');
    expect(calendarRoute(DateTime(2026, 11, 9)), '/calendar?month=2026-11');
  });
}
