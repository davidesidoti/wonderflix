import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/calendar/calendar_day_dialog.dart';
import 'package:wonderflix/features/calendar/calendar_logic.dart';

import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';

final _day = DateTime(2026, 10, 22);
final _air = DateTime.utc(2026, 10, 22, 1);

final _block = testEpisode(
  seriesName: 'Andor',
  season: 3,
  episode: 1,
  last: 3,
  airDate: _air,
);
final _bridge = UpcomingEpisode(
  seriesName: 'Andor',
  seasonNumber: 3,
  episodeNumber: 4,
  episodeTitle: 'Il ponte',
  airDate: _air,
  onServer: true,
);
final _andor = CalendarEntry(
  kind: CalendarEntryKind.series,
  title: 'Andor',
  count: 4,
  episodes: [_block, _bridge],
);
final _weapons = CalendarEntry(
  kind: CalendarEntryKind.movie,
  title: 'Weapons',
  onServer: true,
  movie: testUpcomingMovie(title: 'Weapons'),
);

Future<void> _open(
  WidgetTester tester,
  void Function(CalendarEntry entry) onOpenEntry, {
  bool Function(CalendarEntry entry)? canOpen,
}) async {
  await pumpApp(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showCalendarDay(
            context,
            day: _day,
            entries: [_weapons, _andor],
            onOpenEntry: onOpenEntry,
            canOpen: canOpen ?? (_) => true,
          ),
          child: const Text('apri'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('TheDayListShowsEveryEpisodeAndTime', (tester) async {
    await _open(tester, (_) {});
    expect(find.text('Giovedì 22 ottobre'), findsOneWidget);
    expect(find.text('Weapons'), findsOneWidget);
    expect(find.text('Film · in digitale'), findsOneWidget);
    expect(find.text('Andor'), findsNWidgets(2));
    expect(find.text('S03E01–E03'), findsOneWidget);
    expect(find.text('S03E04 · Il ponte'), findsOneWidget);
    final time = DateFormat.Hm('it').format(_air.toLocal());
    expect(find.text(time), findsNWidgets(2));
    // Il film e l'episodio sul server; il blocco no.
    final onServer = find.text('Sul server');
    expect(onServer, findsNWidgets(2));
    expect(tester.widget<Text>(onServer.first).style?.color, WfColors.online);
  });

  testWidgets('TappingARowClosesAndOpens', (tester) async {
    final opened = <CalendarEntry>[];
    await _open(tester, opened.add);
    await tester.tap(find.text('S03E04 · Il ponte'));
    await tester.pumpAndSettle();
    expect(find.text('Giovedì 22 ottobre'), findsNothing);
    expect(opened, [_andor]);
    // La pagina sotto c'è ancora.
    expect(find.text('apri'), findsOneWidget);
  });

  testWidgets('ADoubleTapPopsOnlyTheDialog', (tester) async {
    final opened = <CalendarEntry>[];
    await _open(tester, opened.add);
    // Due clic prima che la finestra se ne vada (il tocco vero del test
    // viene già ignorato durante l'uscita, il callback no).
    final onTap = tester
        .widget<InkWell>(
          find.ancestor(
            of: find.text('Weapons'),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!;
    onTap();
    onTap();
    await tester.pumpAndSettle();
    expect(find.text('apri'), findsOneWidget);
    expect(opened, [_weapons]);
  });

  testWidgets('ARowThatCannotOpenIsNotClickable', (tester) async {
    final opened = <CalendarEntry>[];
    await _open(tester, opened.add, canOpen: (e) => e != _weapons);
    InkWell row(String text) => tester.widget<InkWell>(
      find.ancestor(of: find.text(text), matching: find.byType(InkWell)),
    );
    expect(row('Weapons').onTap, isNull);
    expect(row('S03E04 · Il ponte').onTap, isNotNull);
    await tester.tap(find.text('Weapons'));
    await tester.pumpAndSettle();
    expect(find.text('Giovedì 22 ottobre'), findsOneWidget);
    expect(opened, isEmpty);
  });
}
