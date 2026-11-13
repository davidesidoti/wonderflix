import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/home_models.dart';
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

CalendarEntry _series(
  String title,
  DateTime airDate, {
  bool onServer = false,
}) => CalendarEntry(
  kind: CalendarEntryKind.series,
  title: title,
  onServer: onServer,
  episodes: [
    UpcomingEpisode(
      seriesName: title,
      seasonNumber: 1,
      episodeNumber: 1,
      airDate: airDate,
      onServer: onServer,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  Map<DateTime, List<CalendarEntry>> entries = const {},
  void Function(DateTime day)? onOpenDay,
  void Function(CalendarEntry entry)? onOpenEntry,
  bool Function(CalendarEntry entry)? canOpen,
  Size surfaceSize = const Size(1440, 900),
  DateTime? now,
  DateTime? selectedDay,
  void Function(DateTime day)? onSelectDay,
}) => pumpApp(
  tester,
  Scaffold(
    body: CalendarMonthGrid(
      month: DateTime(2026, 10),
      today: _today,
      now: now ?? DateTime(2026, 10, 22, 12),
      selectedDay: selectedDay,
      onSelectDay: onSelectDay,
      entries: entries,
      onOpenDay: onOpenDay ?? (_) {},
      onOpenEntry: onOpenEntry ?? (_) {},
      canOpen: canOpen ?? (_) => true,
    ),
  ),
  surfaceSize: surfaceSize,
);

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Finder _day(DateTime d) => find.byKey(Key('calendar-day-${_key(d)}'));

/// La decorazione della casella del giorno.
BoxDecoration _cell(WidgetTester tester, DateTime d) =>
    tester
            .widget<Container>(
              find
                  .descendant(of: _day(d), matching: find.byType(Container))
                  .first,
            )
            .decoration!
        as BoxDecoration;

/// Gli `Opacity` sotto 1 sopra [of].
Finder _dimmed(Finder of) => find.ancestor(
  of: of,
  matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1),
);

void main() {
  testWidgets('TheGridHasFortyTwoDaysFromMonday', (tester) async {
    await _pump(tester);
    final keys = tester
        .widgetList(
          find.byWidgetPredicate((w) {
            final k = w.key;
            return k is ValueKey<String> && k.value.startsWith('calendar-day-');
          }),
        )
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
    // Intestazioni a sinistra, sab e dom più spenti.
    expect(tester.widget<Text>(find.text('lun')).textAlign, TextAlign.left);
    expect(
      tester.widget<Text>(find.text('sab')).style!.color,
      WfColors.cream.withValues(alpha: 0.45),
    );
    expect(
      tester.widget<Text>(find.text('ven')).style!.color,
      WfColors.creamMuted,
    );
  });

  testWidgets('TodayHasAGoldBorder', (tester) async {
    await _pump(tester);
    expect(
      _cell(tester, _today).border,
      Border.all(color: WfColors.gold, width: 2),
    );
    expect(
      _cell(tester, DateTime(2026, 10, 21)).border,
      Border.all(color: Colors.transparent),
    );
    // Passato del mese surface, futuro surfaceHigh, mesi vicini trasparenti.
    expect(_cell(tester, DateTime(2026, 10, 21)).color, WfColors.surface);
    expect(_cell(tester, DateTime(2026, 10, 23)).color, WfColors.surfaceHigh);
    expect(_cell(tester, DateTime(2026, 9, 30)).color, Colors.transparent);
    expect(
      _cell(tester, DateTime(2026, 9, 30)).border,
      Border.all(color: WfColors.surface),
    );
  });

  testWidgets('TodayNumberIsAGoldPillFollowedByToday', (tester) async {
    await _pump(tester);
    expect(find.text('Oggi'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('22'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == WfColors.gold,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('EntriesShowLabelsAndMarks', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      entries: {
        _today: const [_weapons, _andor],
      },
    );
    expect(find.text('Andor ×3'), findsOneWidget);
    expect(find.text('Weapons'), findsOneWidget);
    // Oggi: il film è sul server (✓), la serie non c'è (cerchio).
    expect(
      find.byKey(const Key('calendar-entry-2026-10-22-0-arrived')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('calendar-entry-2026-10-22-0-missing')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('calendar-entry-2026-10-22-1-missing')),
      findsOneWidget,
    );
    // Barretta di 3 px: oro per il film, azzurra per la serie.
    for (final (i, color) in [
      (0, WfColors.gold),
      (1, WfColors.calendarSeriesMark),
    ]) {
      final bar = find.byKey(Key('calendar-entry-2026-10-22-$i-bar'));
      expect(tester.getSize(bar), const Size(3, 12));
      expect(
        (tester.widget<Container>(bar).decoration! as BoxDecoration).color,
        color,
      );
    }
    expect(find.byIcon(LucideIcons.film), findsNothing);
    expect(find.byIcon(LucideIcons.tv), findsNothing);
    expect(find.bySemanticsLabel('Film, Weapons, già sul server'), findsOne);
    expect(
      find.bySemanticsLabel('Serie, Andor ×3, Non ancora arrivato'),
      findsOne,
    );
    expect(find.bySemanticsLabel('Giovedì 22 ottobre: 2 uscite'), findsOne);
    expect(find.bySemanticsLabel('Mercoledì 21 ottobre'), findsOne);
    handle.dispose();
  });

  testWidgets('PastDaysAreDimmedExceptMissingEntries', (tester) async {
    await _pump(
      tester,
      entries: {
        DateTime(2026, 10, 20): const [
          CalendarEntry(
            kind: CalendarEntryKind.movie,
            title: 'Vecchio',
            onServer: true,
          ),
          CalendarEntry(kind: CalendarEntryKind.movie, title: 'Perso'),
        ],
      },
    );
    expect(tester.widget<Opacity>(_dimmed(find.text('Vecchio'))).opacity, 0.42);
    expect(tester.widget<Opacity>(_dimmed(find.text('20'))).opacity, 0.42);
    final missing = find.byKey(
      const Key('calendar-entry-2026-10-20-1-missing'),
    );
    expect(missing, findsOneWidget);
    expect(_dimmed(find.text('Perso')), findsNothing);
    expect(_dimmed(missing), findsNothing);
    // Oggi a piena luce, un giorno dei mesi vicini al 30%.
    expect(_dimmed(find.text('22')), findsNothing);
    expect(tester.widget<Opacity>(_dimmed(find.text('30'))).opacity, 0.30);
  });

  testWidgets('TodayShowsTimesAndChecks', (tester) async {
    await _pump(
      tester,
      entries: {
        _today: [
          _series('Alfa', DateTime(2026, 10, 22, 9), onServer: true),
          _series('Beta', DateTime(2026, 10, 22, 21)),
        ],
      },
    );
    expect(
      find.byKey(const Key('calendar-entry-2026-10-22-0-arrived')),
      findsOneWidget,
    );
    expect(find.text('21:00'), findsOneWidget);
    expect(find.text('09:00'), findsNothing);
    for (final mark in ['arrived', 'missing']) {
      expect(
        find.byKey(Key('calendar-entry-2026-10-22-1-$mark')),
        findsNothing,
      );
    }
  });

  testWidgets('FutureEntriesHaveNoMarks', (tester) async {
    await _pump(
      tester,
      entries: {
        DateTime(2026, 10, 25): [
          _weapons,
          const CalendarEntry(kind: CalendarEntryKind.movie, title: 'Altro'),
          _series('Beta', DateTime(2026, 10, 25, 21)),
        ],
      },
    );
    expect(find.text('Weapons'), findsOneWidget);
    expect(find.text('21:00'), findsNothing);
    for (var i = 0; i < 3; i++) {
      for (final mark in ['missing', 'arrived']) {
        expect(
          find.byKey(Key('calendar-entry-2026-10-25-$i-$mark')),
          findsNothing,
        );
      }
    }
  });

  testWidgets('ScreenReadersCanActivateDaysAndEntries', (tester) async {
    final handle = tester.ensureSemantics();
    final days = <DateTime>[];
    final opened = <CalendarEntry>[];
    await _pump(
      tester,
      entries: {
        _today: const [_weapons],
      },
      onOpenDay: days.add,
      onOpenEntry: opened.add,
    );
    final cell = tester.getSemantics(
      find.bySemanticsLabel('Giovedì 22 ottobre: 1 uscita'),
    );
    final chip = tester.getSemantics(
      find.bySemanticsLabel('Film, Weapons, già sul server'),
    );
    expect(cell.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(chip.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    final empty = tester.getSemantics(
      find.bySemanticsLabel('Mercoledì 21 ottobre'),
    );
    expect(empty.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    tester.semantics.tap(
      find.semantics.byLabel('Giovedì 22 ottobre: 1 uscita'),
    );
    tester.semantics.tap(
      find.semantics.byLabel('Film, Weapons, già sul server'),
    );
    expect(days, [_today]);
    expect(opened, [_weapons]);
    handle.dispose();
  });

  testWidgets('TooManyEntriesBecomePlusNOthers', (tester) async {
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
    expect(find.text('+${8 - shown} altre'), findsOneWidget);
  });

  testWidgets('EntriesHaveATooltip', (tester) async {
    await _pump(
      tester,
      entries: {
        _today: const [_weapons, _andor],
      },
    );
    expect(find.byTooltip('Film: Weapons'), findsOneWidget);
    expect(find.byTooltip('Serie: Andor ×3'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.text('Weapons'), matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, 'Film: Weapons');
    expect(tooltip.waitDuration, const Duration(milliseconds: 500));
  });

  testWidgets('HoveringLightsTheCellAndTheOpenableEntry', (tester) async {
    await _pump(
      tester,
      entries: {
        _today: const [_andor],
        DateTime(2026, 10, 23): const [_weapons],
      },
      canOpen: (e) => e != _andor,
    );
    Finder litEntry(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == WfColors.border,
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Weapons')));
    await tester.pump();
    expect(
      _cell(tester, DateTime(2026, 10, 23)).border,
      Border.all(color: const Color(0xFF3A3A3A)),
    );
    expect(litEntry('Weapons'), findsOneWidget);
    // Una voce che non si apre non cambia fondo; oggi tiene il bordo oro.
    await mouse.moveTo(tester.getCenter(find.text('Andor ×3')));
    await tester.pump();
    expect(litEntry('Andor ×3'), findsNothing);
    expect(
      _cell(tester, _today).border,
      Border.all(color: WfColors.gold, width: 2),
    );
  });

  testWidgets('TappingAnEntryOpensItTappingTheDayOpensTheList', (tester) async {
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
        _today: [
          _weapons,
          _series('Beta', DateTime(2026, 10, 22, 21)),
          const CalendarEntry(kind: CalendarEntryKind.movie, title: 'Perso'),
        ],
      },
      onOpenDay: days.add,
      surfaceSize: const Size(600, 900),
    );
    expect(find.text('Weapons'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    BoxDecoration dot(int i) =>
        tester
                .widget<Container>(
                  find.byKey(Key('calendar-dot-2026-10-22-$i')),
                )
                .decoration!
            as BoxDecoration;
    expect(dot(0).color, WfColors.gold);
    expect(dot(1).color, WfColors.calendarSeriesMark);
    // Una voce non sul server (oggi, film) è un cerchio vuoto oro.
    expect(dot(2).color, isNull);
    expect(dot(2).border, Border.all(color: WfColors.gold, width: 1.2));
    await tester.tap(_day(_today));
    expect(days, [_today]);
  });

  testWidgets('SelectionModeSelectsInsteadOfOpening', (tester) async {
    final selected = <DateTime>[];
    final opened = <DateTime>[];
    await _pump(
      tester,
      entries: {
        _today: const [_weapons, _andor],
      },
      onOpenDay: opened.add,
      onSelectDay: selected.add,
      selectedDay: DateTime(2026, 10, 14),
    );
    // Puntini anche a 1440 px, caselle alte 48, griglia di altezza fissa.
    expect(find.text('Weapons'), findsNothing);
    expect(find.byKey(const Key('calendar-dot-2026-10-22-0')), findsOneWidget);
    expect(find.byKey(const Key('calendar-dot-2026-10-22-1')), findsOneWidget);
    expect(tester.getSize(_day(_today)).height, 48);
    // Il genitore ha misura obbligata: la griglia resta alta 24 + 6*48 + 5*4.
    expect(
      tester.getRect(_day(DateTime(2026, 11, 8))).bottom -
          tester.getTopLeft(find.byType(CalendarMonthGrid)).dy,
      24 + 6 * 48 + 5 * 4,
    );
    // Il giorno selezionato ha il suo fondo.
    expect(
      _cell(tester, DateTime(2026, 10, 14)).color,
      const Color(0xFF2A2418),
    );
    expect(_cell(tester, DateTime(2026, 10, 15)).color, WfColors.surface);
    // Ogni giorno si seleziona: vuoto, pieno, di un mese vicino.
    await tester.tap(_day(DateTime(2026, 10, 14)));
    await tester.tap(_day(_today));
    await tester.tap(_day(DateTime(2026, 11, 3)));
    expect(selected, [DateTime(2026, 10, 14), _today, DateTime(2026, 11, 3)]);
    expect(opened, isEmpty);
    // Invio seleziona il giorno della tastiera.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    // La tastiera parte dal giorno selezionato, non da oggi.
    expect(selected.last, DateTime(2026, 10, 15));
    expect(opened, isEmpty);
  });

  testWidgets('TheSelectedDayIsSelectedForScreenReaders', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      onSelectDay: (_) {},
      selectedDay: DateTime(2026, 10, 14),
    );
    expect(
      tester.getSemantics(_day(DateTime(2026, 10, 14))),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(_day(DateTime(2026, 10, 15))),
      isSemantics(isSelected: false),
    );
    handle.dispose();
  });

  testWidgets('FourDotsFitOnOneLineOnA360Phone', (tester) async {
    // 360 px meno i 16 px di margine della pagina per lato.
    await _pump(
      tester,
      entries: {
        _today: [
          _weapons,
          _series('Beta', DateTime(2026, 10, 22, 21)),
          _andor,
          const CalendarEntry(kind: CalendarEntryKind.movie, title: 'Perso'),
        ],
        DateTime(2026, 10, 23): const [_weapons, _andor, _weapons, _andor],
      },
      onSelectDay: (_) {},
      selectedDay: _today,
      surfaceSize: const Size(328, 800),
    );
    for (final day in ['2026-10-22', '2026-10-23']) {
      final top = tester.getTopLeft(find.byKey(Key('calendar-dot-$day-0'))).dy;
      for (var i = 1; i < 4; i++) {
        expect(
          tester.getTopLeft(find.byKey(Key('calendar-dot-$day-$i'))).dy,
          top,
          reason: '$day, puntino $i',
        );
      }
    }
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
    expect(
      _cell(tester, DateTime(2026, 10, 30)).border,
      Border.all(color: WfColors.cream, width: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(days, [DateTime(2026, 10, 30)]);
    // Fuori dai 42 giorni non si va.
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(days, [DateTime(2026, 10, 30)], reason: '6 nov senza voci');
  });

  testWidgets('EmptyDaysAreNotButtons', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      entries: {
        _today: const [_weapons],
      },
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Mercoledì 21 ottobre')),
      isSemantics(isButton: false),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Giovedì 22 ottobre: 1 uscita'),
      ),
      isSemantics(isButton: true),
    );
    handle.dispose();
  });

  testWidgets('AnEntryThatCannotOpenIsNotClickable', (tester) async {
    final handle = tester.ensureSemantics();
    final opened = <CalendarEntry>[];
    final days = <DateTime>[];
    await _pump(
      tester,
      entries: {
        _today: const [_weapons, _andor],
      },
      onOpenDay: days.add,
      onOpenEntry: opened.add,
      canOpen: (e) => e != _weapons,
    );
    final weapons = tester.getSemantics(
      find.bySemanticsLabel('Film, Weapons, già sul server'),
    );
    final andor = tester.getSemantics(
      find.bySemanticsLabel('Serie, Andor ×3, Non ancora arrivato'),
    );
    expect(weapons.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(andor.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    Finder clickCursors(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.click,
      ),
    );
    // Solo la casella del giorno; la voce aperta ha la sua.
    expect(clickCursors('Weapons'), findsOneWidget);
    expect(clickCursors('Andor ×3'), findsNWidgets(2));
    // Il tocco va alla casella: si apre l'elenco del giorno, non la voce.
    await tester.tap(find.text('Weapons'));
    expect(opened, isEmpty);
    expect(days, [_today]);
    handle.dispose();
  });

  testWidgets('AShortCellShowsOnlyPlusN', (tester) async {
    final movies = [
      for (var i = 0; i < 3; i++)
        CalendarEntry(kind: CalendarEntryKind.movie, title: 'Film $i'),
    ];
    // Celle di ~59 px: due voci (62 px) non ci stanno.
    await _pump(
      tester,
      entries: {_today: movies},
      surfaceSize: const Size(1440, 400),
    );
    final cell = tester.getRect(_day(_today));
    expect(
      cell.height,
      lessThan(
        CalendarMonthGrid.dayRowHeight + 2 * CalendarMonthGrid.entryHeight,
      ),
    );
    for (var i = 0; i < 3; i++) {
      expect(find.text('Film $i'), findsNothing);
    }
    final more = find.text('+3 altre');
    expect(more, findsOneWidget);
    expect(tester.getRect(more).bottom, lessThanOrEqualTo(cell.bottom));
  });
}
