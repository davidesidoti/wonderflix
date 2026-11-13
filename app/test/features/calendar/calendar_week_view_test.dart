import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/calendar/calendar_logic.dart';
import 'package:wonderflix/features/calendar/calendar_week_view.dart';

import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';

final _now = DateTime(2026, 11, 13, 22, 26);
final _today = DateTime(2026, 11, 13);

final _bear = CalendarEntry(
  kind: CalendarEntryKind.series,
  title: 'The Bear',
  episodes: [testEpisode(airDate: DateTime(2026, 11, 13, 9), onServer: true)],
);

Future<void> _pump(
  WidgetTester tester, {
  Map<DateTime, List<CalendarEntry>>? entries,
  bool knownEmpty = false,
  bool compact = false,
  void Function(CalendarEntry)? onOpen,
}) => pumpApp(
  tester,
  Scaffold(
    body: CalendarWeekView(
      today: _today,
      now: _now,
      entries:
          entries ??
          {
            _today: [_bear],
          },
      knownEmpty: knownEmpty,
      onOpenEntry: onOpen ?? (_) {},
      canOpen: (_) => true,
      compact: compact,
    ),
  ),
  surfaceSize: compact ? const Size(390, 844) : const Size(1440, 1200),
);

void main() {
  testWidgets('SevenHeadingsFromToday', (tester) async {
    await _pump(tester);
    expect(find.text('Oggi'), findsOneWidget);
    expect(find.text('Domani'), findsOneWidget);
    expect(
      find.byKey(const Key('calendar-heading-2026-11-19')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('calendar-heading-2026-11-20')), findsNothing);
  });

  testWidgets('AnEmptyDaySaysSo', (tester) async {
    await _pump(tester);
    // oggi ha una voce, gli altri sei giorni no
    expect(find.text('Nessuna uscita'), findsNWidgets(6));
  });

  testWidgets('AnEmptyWeekSaysItOnce', (tester) async {
    await _pump(tester, entries: {}, knownEmpty: true);
    expect(find.text('Nessuna uscita nei prossimi 7 giorni'), findsOneWidget);
    expect(find.text('Nessuna uscita'), findsNothing);
    expect(find.text('Oggi'), findsOneWidget);
  });

  testWidgets('AFailingServiceDoesNotSayTheWeekIsEmpty', (tester) async {
    await _pump(tester, entries: {});
    expect(find.text('Nessuna uscita nei prossimi 7 giorni'), findsNothing);
  });

  testWidgets('TappingARowOpensIt', (tester) async {
    CalendarEntry? opened;
    await _pump(tester, onOpen: (e) => opened = e);
    await tester.tap(find.text('The Bear'));
    expect(opened, same(_bear));
  });

  testWidgets('CompactRowsShowOnlyTheMark', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, compact: true);
    expect(find.text('Sul server'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Sul server')), findsOneWidget);
    handle.dispose();
  });
}
