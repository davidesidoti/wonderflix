import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/calendar/calendar_day_dialog.dart';
import 'package:wonderflix/features/calendar/calendar_release_row.dart';
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

// Dopo l'uscita degli episodi di prova, e un altro giorno da `_day`.
final _now = DateTime(2026, 10, 25, 12);
final _today = DateTime(2026, 10, 25);

Future<void> _open(
  WidgetTester tester,
  void Function(CalendarEntry entry) onOpenEntry, {
  bool Function(CalendarEntry entry)? canOpen,
  Size surfaceSize = const Size(1440, 900),
  DateTime? day,
  DateTime? today,
  DateTime? now,
  List<CalendarEntry>? entries,
}) async {
  await pumpApp(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showCalendarDay(
            context,
            day: day ?? _day,
            today: today ?? _today,
            now: now ?? _now,
            entries: entries ?? [_weapons, _andor],
            onOpenEntry: onOpenEntry,
            canOpen: canOpen ?? (_) => true,
          ),
          child: const Text('apri'),
        ),
      ),
    ),
    surfaceSize: surfaceSize,
  );
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
}

CalendarEntry _show(
  String name,
  DateTime air, {
  String? title,
  bool onServer = false,
}) => CalendarEntry(
  kind: CalendarEntryKind.series,
  title: name,
  episodes: [
    UpcomingEpisode(
      seriesName: name,
      seasonNumber: 1,
      episodeNumber: 8,
      episodeTitle: title,
      airDate: air,
      onServer: onServer,
    ),
  ],
);

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

  testWidgets('RowsAreInTimeOrder', (tester) async {
    await _open(
      tester,
      (_) {},
      entries: [
        _show('Tulsa King', DateTime.utc(2026, 10, 22, 9)),
        _show('Overgeared', DateTime.utc(2026, 10, 22, 15, 30)),
        _show("Grey's Anatomy", DateTime.utc(2026, 10, 22, 3)),
        _weapons,
      ],
    );
    double top(String t) => tester.getTopLeft(find.text(t)).dy;
    final order = ['Weapons', "Grey's Anatomy", 'Tulsa King', 'Overgeared'];
    for (var i = 1; i < order.length; i++) {
      expect(top(order[i - 1]), lessThan(top(order[i])), reason: order[i]);
    }
  });

  testWidgets('TbaIsHidden', (tester) async {
    await _open(
      tester,
      (_) {},
      entries: [_show('Tulsa King', _air, title: ' tba ')],
    );
    expect(find.text('S01E08'), findsOneWidget);
    expect(
      find.textContaining(RegExp('tba', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('TheDialogSaysHowManyAndHowManyAreHere', (tester) async {
    List<CalendarEntry> five({required int here}) => [
      for (var i = 0; i < 5; i++)
        _show('Serie $i', _air.add(Duration(hours: i)), onServer: i < here),
    ];
    await _open(tester, (_) {}, entries: five(here: 4));
    expect(find.text('5 uscite · 4 già sul server'), findsOneWidget);
  });

  testWidgets('TheSummaryOmitsTheServerPartWhenNoneIsHere', (tester) async {
    await _open(
      tester,
      (_) {},
      entries: [
        for (var i = 0; i < 5; i++)
          _show('Serie $i', _air.add(Duration(hours: i))),
      ],
    );
    expect(find.text('5 uscite'), findsOneWidget);
  });

  testWidgets('TodayAndTomorrowHaveAPill', (tester) async {
    await _open(tester, (_) {}, day: _today);
    expect(find.text('Oggi'), findsOneWidget);
    expect(find.text('Domani'), findsNothing);
  });

  testWidgets('TomorrowHasAPill', (tester) async {
    await _open(tester, (_) {}, day: DateTime(2026, 10, 26));
    expect(find.text('Domani'), findsOneWidget);
    expect(find.text('Oggi'), findsNothing);
  });

  testWidgets('OtherDaysHaveNoPill', (tester) async {
    await _open(tester, (_) {});
    expect(find.text('Oggi'), findsNothing);
    expect(find.text('Domani'), findsNothing);
  });

  testWidgets('EachRowShowsItsState', (tester) async {
    await _open(
      tester,
      (_) {},
      entries: [
        _show('Qui', _air, onServer: true),
        _show('Manca', _air.add(const Duration(hours: 1))),
        _show('Futuro', DateTime.utc(2026, 10, 30)),
      ],
    );
    Finder state(String s, String show) => find.descendant(
      of: find.ancestor(of: find.text(show), matching: find.byType(InkWell)),
      matching: find.text(s),
    );
    expect(state('Sul server', 'Qui'), findsOneWidget);
    expect(state('Non ancora arrivato', 'Manca'), findsOneWidget);
    expect(state('Sul server', 'Futuro'), findsNothing);
    expect(state('Non ancora arrivato', 'Futuro'), findsNothing);
  });

  group('CalendarDayList', () {
    Future<void> list(
      WidgetTester tester,
      DateTime day, {
      List<CalendarEntry> entries = const [],
    }) => pumpApp(
      tester,
      Scaffold(
        body: CalendarDayList(
          day: day,
          today: _today,
          now: _now,
          entries: entries,
          onOpenEntry: (_) {},
          canOpen: (_) => true,
        ),
      ),
      surfaceSize: const Size(1440, 900),
    );

    testWidgets('TodayHasAGoldHeadingAndTheDate', (tester) async {
      await list(tester, _today);
      expect(
        find.byKey(const Key('calendar-heading-2026-10-25')),
        findsOneWidget,
      );
      final oggi = tester.widget<Text>(find.text('Oggi'));
      expect(oggi.style?.color, WfColors.gold);
      expect(find.text('domenica 25 ottobre'), findsOneWidget);
    });

    testWidgets('TomorrowHasItsNameAndTheDate', (tester) async {
      await list(tester, DateTime(2026, 10, 26));
      expect(find.text('Domani'), findsOneWidget);
      expect(find.text('lunedì 26 ottobre'), findsOneWidget);
    });

    testWidgets('OtherDaysHaveTheCapitalizedDate', (tester) async {
      await list(tester, _day);
      expect(find.text('Giovedì 22 ottobre'), findsOneWidget);
    });

    testWidgets('AnEmptyDaySaysSo', (tester) async {
      await list(tester, _day);
      expect(find.text('Nessuna uscita'), findsOneWidget);
    });

    testWidgets('ARowIsShownWhenThereAreEntries', (tester) async {
      await list(tester, _day, entries: [_weapons]);
      expect(find.text('Weapons'), findsOneWidget);
      expect(find.text('Nessuna uscita'), findsNothing);
    });
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets(
      'telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow',
      (tester) async {
        await _open(tester, (_) {}, surfaceSize: size);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
