import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/calendar/calendar_logic.dart';
import 'package:wonderflix/features/calendar/calendar_month_grid.dart';

import '../../support/pump_app.dart';

const _andor = CalendarEntry(
  kind: CalendarEntryKind.series,
  title: 'Andor',
  count: 3,
);
const _weapons = CalendarEntry(
  kind: CalendarEntryKind.movie,
  title: 'Weapons',
  onServer: true,
);

final _today = DateTime(2026, 10, 22);

Future<void> _pump(
  WidgetTester tester, {
  Map<DateTime, List<CalendarEntry>> entries = const {},
  void Function(DateTime day)? onOpenDay,
  void Function(CalendarEntry entry)? onOpenEntry,
  Size surfaceSize = const Size(1440, 900),
}) => pumpApp(
  tester,
  Scaffold(
    body: CalendarMonthGrid(
      month: DateTime(2026, 10),
      today: _today,
      entries: entries,
      onOpenDay: onOpenDay ?? (_) {},
      onOpenEntry: onOpenEntry ?? (_) {},
    ),
  ),
  surfaceSize: surfaceSize,
);

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Finder _day(DateTime d) => find.byKey(Key('calendar-day-${_key(d)}'));

void main() {
  testWidgets('TheGridHasFortyTwoDaysFromMonday', (tester) async {
    await _pump(tester);
    final keys = tester
        .widgetList(find.byWidgetPredicate((w) {
          final k = w.key;
          return k is ValueKey<String> && k.value.startsWith('calendar-day-');
        }))
        .map((w) => (w.key! as ValueKey<String>).value)
        .toList();
    expect(keys, hasLength(42));
    expect(keys.first, 'calendar-day-2026-09-28');
    expect(keys.last, 'calendar-day-2026-11-08');
    final headers = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];
    for (final h in headers) {
      expect(find.text(h), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.text('lun')).dx,
      lessThan(tester.getTopLeft(find.text('mar')).dx),
    );
  });

  testWidgets('TodayHasAGoldBorder', (tester) async {
    await _pump(tester);
    BoxDecoration deco(DateTime d) =>
        tester
                .widget<Container>(
                  find
                      .descendant(of: _day(d), matching: find.byType(Container))
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(
      deco(_today).border,
      Border.all(color: WfColors.gold),
    );
    expect(deco(DateTime(2026, 10, 21)).border, isNull);
  });

  testWidgets('EntriesShowLabelsAndTheOnServerDot', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      entries: {
        _today: const [_weapons, _andor],
      },
    );
    expect(find.text('Andor ×3'), findsOneWidget);
    expect(find.text('Weapons'), findsOneWidget);
    expect(
      find.byKey(const Key('calendar-entry-2026-10-22-0-server')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('calendar-entry-2026-10-22-1-server')),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Film, Weapons, già sul server'), findsOne);
    expect(find.bySemanticsLabel('Serie, Andor ×3'), findsOne);
    expect(find.bySemanticsLabel('Giovedì 22 ottobre: 2 uscite'), findsOne);
    expect(find.bySemanticsLabel('Mercoledì 21 ottobre'), findsOne);
    handle.dispose();
  });

  testWidgets('TooManyEntriesBecomePlusN', (tester) async {
    final movies = [
      for (var i = 0; i < 8; i++)
        CalendarEntry(kind: CalendarEntryKind.movie, title: 'Film $i'),
    ];
    await _pump(tester, entries: {_today: movies});
    final height = tester.getSize(_day(_today)).height;
    final rows = max(
      CalendarMonthGrid.minEntries,
      (height - CalendarMonthGrid.dayRowHeight) ~/
          CalendarMonthGrid.entryHeight,
    );
    expect(rows, lessThan(8), reason: 'la prova deve sforare');
    final shown = rows - 1;
    for (var i = 0; i < 8; i++) {
      expect(find.text('Film $i'), i < shown ? findsOneWidget : findsNothing);
    }
    expect(find.text('+${8 - shown}'), findsOneWidget);
  });

  testWidgets('TappingAnEntryOpensItTappingTheDayOpensTheList', (
    tester,
  ) async {
    final movies = [
      for (var i = 0; i < 8; i++)
        CalendarEntry(kind: CalendarEntryKind.movie, title: 'Film $i'),
    ];
    final opened = <CalendarEntry>[];
    final days = <DateTime>[];
    await _pump(
      tester,
      entries: {_today: movies},
      onOpenDay: days.add,
      onOpenEntry: opened.add,
    );
    await tester.tap(find.text('Film 1'));
    expect(opened, [movies[1]]);
    expect(days, isEmpty);
    await tester.tap(find.textContaining('+'));
    expect(days, [_today]);
    // Un giorno senza voci non apre niente.
    await tester.tap(_day(DateTime(2026, 10, 21)));
    expect(days, [_today]);
    expect(opened, [movies[1]]);
  });

  testWidgets('NarrowCellsShowDots', (tester) async {
    final days = <DateTime>[];
    await _pump(
      tester,
      entries: {
        _today: const [_weapons, _andor],
      },
      onOpenDay: days.add,
      surfaceSize: const Size(600, 900),
    );
    expect(find.text('Weapons'), findsNothing);
    expect(find.text('Andor ×3'), findsNothing);
    expect(find.byKey(const Key('calendar-dot-2026-10-22-0')), findsOneWidget);
    expect(find.byKey(const Key('calendar-dot-2026-10-22-1')), findsOneWidget);
    await tester.tap(_day(_today));
    expect(days, [_today]);
  });

  testWidgets('ArrowsAndEnterOpenTheChosenDay', (tester) async {
    final days = <DateTime>[];
    await _pump(
      tester,
      entries: {
        DateTime(2026, 10, 30): const [_weapons],
      },
      onOpenDay: days.add,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final deco =
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: _day(DateTime(2026, 10, 30)),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(deco.border, Border.all(color: WfColors.cream, width: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(days, [DateTime(2026, 10, 30)]);
    // Fuori dai 42 giorni non si va.
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(days, [DateTime(2026, 10, 30)], reason: '6 nov senza voci');
  });
}
