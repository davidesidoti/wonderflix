import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/calendar/calendar_logic.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/home_fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  final l = lookupAppLocalizations(const Locale('it'));

  test('GridDaysAreFortyTwoConsecutiveDaysFromMonday', () {
    final oct = gridDaysOf(DateTime(2026, 10));
    expect(oct.first, DateTime(2026, 9, 28));
    expect(oct.last, DateTime(2026, 11, 8));
    expect(gridDaysOf(DateTime(2026, 2)).first, DateTime(2026, 1, 26));
    expect(gridDaysOf(DateTime(2026, 6)).first, DateTime(2026, 6));
    for (final month in [DateTime(2026, 3), DateTime(2026, 10)]) {
      final days = gridDaysOf(month);
      expect(days, hasLength(calendarGridLength));
      for (var i = 0; i < days.length; i++) {
        final d = days[i];
        expect(d, DateTime(d.year, d.month, d.day), reason: 'mezzanotte');
        expect(
          d,
          DateTime(days.first.year, days.first.month, days.first.day + i),
        );
      }
    }
  });

  test('ThePeriodEndsTheDayAfterTheGrid', () {
    final p = calendarPeriod(DateTime(2026, 10));
    expect(p.start, DateTime(2026, 9, 28));
    expect(p.end, DateTime(2026, 11, 9));
    expect(calendarMonthOf(DateTime(2026, 10, 22, 15)), DateTime(2026, 10));
  });

  test('EpisodesUseTheLocalDayMoviesTheUtcDay', () {
    final air = DateTime.utc(2026, 10, 22, 23, 30);
    final local = air.toLocal();
    final map = entriesByDay(
      CalendarPage(
        episodes: [testEpisode(airDate: air)],
        movies: [
          testUpcomingMovie(
            digitalRelease: DateTime.utc(2026, 11, 12).toLocal(),
          ),
          // 13 novembre in locale (CET): la chiave viene dal giorno UTC.
          testUpcomingMovie(
            title: 'Late',
            tmdbId: 9,
            digitalRelease: DateTime.utc(2026, 11, 12, 23, 30),
          ),
        ],
      ),
    );
    expect(map[DateTime(2026, 11, 12)], hasLength(2));
    expect(map.containsKey(DateTime(2026, 11, 13)), isFalse);
    expect(map[DateTime(local.year, local.month, local.day)], hasLength(1));
    expect(map[DateTime(2026, 11, 12)]!.first.kind, CalendarEntryKind.movie);
    expect(map, hasLength(2));
  });

  test('GroupingPrefersTvdbIdThenTmdbIdThenName', () {
    final air = DateTime.utc(2026, 10, 22, 12);
    List<CalendarEntry> group(List<UpcomingEpisode> eps) =>
        entriesByDay(CalendarPage(episodes: eps)).values.single;
    // stesso tvdbId, tmdbId diversi: una voce
    expect(
      group([
        testEpisode(airDate: air, tvdbId: 5, tmdbId: 1),
        testEpisode(airDate: air, tvdbId: 5, tmdbId: 2, episode: 6),
      ]),
      hasLength(1),
    );
    // niente id: si unisce per nome senza badare alle maiuscole
    final byName = group([
      testEpisode(seriesName: 'Andor', airDate: air, tmdbId: null),
      testEpisode(seriesName: 'andor', airDate: air, tmdbId: null, episode: 6),
    ]);
    expect(byName, hasLength(1));
    expect(byName.single.count, 2);
  });

  test('ABackwardsBlockCountsAsOneEpisode', () {
    final air = DateTime.utc(2026, 10, 22, 12);
    final entry = entriesByDay(
      CalendarPage(episodes: [testEpisode(episode: 5, last: 3, airDate: air)]),
    ).values.single.single;
    expect(entry.count, 1);
  });

  test('EpisodesOfOneSeriesInADayAreOneEntry', () {
    final air = DateTime.utc(2026, 10, 22, 23, 30);
    final map = entriesByDay(
      CalendarPage(
        episodes: [
          testEpisode(
            seriesName: 'Andor',
            season: 3,
            episode: 1,
            last: 3,
            airDate: air,
            onServer: true,
          ),
          testEpisode(seriesName: 'andor', season: 3, episode: 4, airDate: air),
          testEpisode(
            seriesName: 'Other',
            airDate: air,
            onServer: true,
            tmdbId: 2,
          ),
        ],
      ),
    );
    final entries = map.values.single;
    expect(entries, hasLength(2));
    final andor = entries.firstWhere((e) => e.title == 'Andor');
    expect(andor.count, 4);
    expect(andor.onServer, isFalse);
    expect(andor.episodes, hasLength(2));
    final other = entries.firstWhere((e) => e.title == 'Other');
    expect(other.count, 1);
    expect(other.onServer, isTrue);
  });

  test('MoviesComeFirstThenSeriesByTime', () {
    final day = DateTime.utc(2026, 10, 22, 12);
    final map = entriesByDay(
      CalendarPage(
        episodes: [
          testEpisode(seriesName: 'B', airDate: day, tmdbId: 2),
          testEpisode(seriesName: 'a', airDate: day, tmdbId: 1),
          testEpisode(
            seriesName: 'Z',
            airDate: day.subtract(const Duration(hours: 1)),
            tmdbId: 5,
          ),
        ],
        movies: [
          testUpcomingMovie(
            title: 'b',
            tmdbId: 3,
            digitalRelease: DateTime.utc(2026, 10, 22),
          ),
          testUpcomingMovie(
            title: 'A',
            tmdbId: 4,
            digitalRelease: DateTime.utc(2026, 10, 22),
          ),
        ],
      ),
    );
    final day22 = map[dayKey(day.toLocal())]!;
    // Il film del 22 UTC e le serie del 22 locale: stesso giorno solo se
    // il fuso non sposta mezzogiorno UTC. A parità d'ora vince il nome.
    expect(day22.map((e) => e.title), ['A', 'b', 'Z', 'a', 'B']);
  });

  test('EpisodeStateFollowsAirTimeAndServer', () {
    final now = DateTime(2026, 11, 13, 22, 26);
    expect(
      episodeState(
        testEpisode(airDate: DateTime(2026, 11, 13, 15, 30), onServer: false),
        now,
      ),
      CalendarEntryState.missing,
    );
    expect(
      episodeState(
        testEpisode(airDate: DateTime(2026, 11, 13, 9), onServer: true),
        now,
      ),
      CalendarEntryState.arrived,
    );
    expect(
      episodeState(
        testEpisode(airDate: DateTime(2026, 11, 13, 23), onServer: false),
        now,
      ),
      CalendarEntryState.upcoming,
    );
  });

  test('ARowStateIsTheMovieDayOrTheEpisodeTime', () {
    final day = DateTime(2026, 11, 13);
    final now = DateTime(2026, 11, 13, 22, 26);
    const movie = CalendarEntry(
      kind: CalendarEntryKind.movie,
      title: 'Odissea',
      onServer: true,
    );
    expect(
      calendarRowState(const CalendarRow(movie), day: day, now: now),
      CalendarEntryState.arrived,
    );
    final late = testEpisode(airDate: DateTime(2026, 11, 13, 23));
    final show = CalendarEntry(
      kind: CalendarEntryKind.series,
      title: 'The Bear',
      episodes: [late],
    );
    // una riga-episodio guarda l'ora del suo episodio
    expect(
      calendarRowState(CalendarRow(show, late), day: day, now: now),
      CalendarEntryState.upcoming,
    );
  });

  test('AMovieCountsFromItsWholeDay', () {
    const odissea = CalendarEntry(
      kind: CalendarEntryKind.movie,
      title: 'Odissea',
    );
    final now = DateTime(2026, 11, 13, 0, 5);
    expect(
      calendarEntryState(odissea, day: DateTime(2026, 11, 13), now: now),
      CalendarEntryState.missing,
    );
    expect(
      calendarEntryState(odissea, day: DateTime(2026, 11, 14), now: now),
      CalendarEntryState.upcoming,
    );
    expect(
      calendarEntryState(
        const CalendarEntry(
          kind: CalendarEntryKind.movie,
          title: 'X',
          onServer: true,
        ),
        day: DateTime(2026, 11, 12),
        now: now,
      ),
      CalendarEntryState.arrived,
    );
  });

  test('AGroupIsMissingIfAnAiredEpisodeIsMissing', () {
    final now = DateTime(2026, 11, 20, 18, 20);
    CalendarEntry percy({required bool firstOnServer}) => CalendarEntry(
      kind: CalendarEntryKind.series,
      title: 'Percy Jackson',
      count: 2,
      episodes: [
        testEpisode(
          episode: 1,
          airDate: DateTime(2026, 11, 20, 18),
          onServer: firstOnServer,
        ),
        testEpisode(episode: 2, airDate: DateTime(2026, 11, 20, 18, 40)),
      ],
    );
    final day = DateTime(2026, 11, 20);
    expect(
      calendarEntryState(percy(firstOnServer: true), day: day, now: now),
      CalendarEntryState.upcoming,
    );
    expect(
      calendarEntryState(percy(firstOnServer: false), day: day, now: now),
      CalendarEntryState.missing,
    );
    // a fine serata anche il secondo è uscito e manca
    expect(
      calendarEntryState(
        percy(firstOnServer: true),
        day: day,
        now: DateTime(2026, 11, 20, 19),
      ),
      CalendarEntryState.missing,
    );
    final done = CalendarEntry(
      kind: CalendarEntryKind.series,
      title: 'Done',
      episodes: [
        testEpisode(airDate: DateTime(2026, 11, 20, 18), onServer: true),
      ],
    );
    expect(
      calendarEntryState(done, day: day, now: now),
      CalendarEntryState.arrived,
    );
  });

  test('ASeriesWithoutEpisodesCountsLikeAMovie', () {
    const s = CalendarEntry(kind: CalendarEntryKind.series, title: 'S');
    final now = DateTime(2026, 11, 13, 12);
    expect(
      calendarEntryState(s, day: DateTime(2026, 11, 13), now: now),
      CalendarEntryState.missing,
    );
    expect(
      calendarEntryState(s, day: DateTime(2026, 11, 14), now: now),
      CalendarEntryState.upcoming,
    );
  });

  CalendarPage orderPage() => CalendarPage(
    episodes: [
      testEpisode(
        seriesName: 'Overgeared',
        airDate: DateTime(2026, 11, 13, 15, 30),
        tmdbId: 1,
      ),
      testEpisode(
        seriesName: 'Tulsa King',
        airDate: DateTime(2026, 11, 13, 9),
        tmdbId: 2,
      ),
      testEpisode(
        seriesName: 'WAR (2026)',
        airDate: DateTime(2026, 11, 13, 3),
        tmdbId: 3,
      ),
      testEpisode(
        seriesName: 'MobLand',
        airDate: DateTime(2026, 11, 13, 9),
        tmdbId: 4,
      ),
      testEpisode(
        seriesName: "Grey's Anatomy",
        airDate: DateTime(2026, 11, 13, 3),
        tmdbId: 5,
      ),
    ],
    movies: [
      testUpcomingMovie(
        title: 'Odissea',
        tmdbId: 6,
        digitalRelease: DateTime.utc(2026, 11, 13),
      ),
    ],
  );
  const orderedTitles = [
    'Odissea',
    "Grey's Anatomy",
    'WAR (2026)',
    'MobLand',
    'Tulsa King',
    'Overgeared',
  ];

  test('RowsAreMoviesThenEpisodesByTime', () {
    final entries = entriesByDay(orderPage()).values.single;
    // Sparse in ingresso: l'ordine delle righe non dipende da quello delle voci.
    final rows = calendarRows(entries.reversed.toList());
    expect(rows.map((r) => r.entry.title), orderedTitles);
    expect(rows.first.episode, isNull);
    expect(rows.last.episode!.seriesName, 'Overgeared');
  });

  test('RowsOfAGroupFollowSeasonAndEpisode', () {
    final air = DateTime(2026, 11, 13, 20);
    final entry = entriesByDay(
      CalendarPage(
        episodes: [
          testEpisode(season: 2, episode: 1, airDate: air),
          testEpisode(season: 1, episode: 9, airDate: air),
          testEpisode(season: 1, episode: 2, airDate: air),
        ],
      ),
    ).values.single.single;
    expect(entry.episodes.map((e) => (e.seasonNumber, e.episodeNumber)), [
      (1, 2),
      (1, 9),
      (2, 1),
    ]);
    expect(calendarRows([entry]), hasLength(3));
  });

  test('EntriesByDayPutsSeriesInTimeOrder', () {
    final entries = entriesByDay(orderPage()).values.single;
    expect(entries.map((e) => e.title), orderedTitles);
  });

  test('TbaIsNoTitle', () {
    for (final t in [null, '', 'TBA', 'tba', ' TBA ', 'TBD']) {
      expect(episodeTitleOrNull(t), isNull, reason: '$t');
    }
    expect(episodeTitleOrNull('Till I Collapse'), 'Till I Collapse');
  });

  test('WeekDaysAndPeriodCrossTheMonth', () {
    final today = DateTime(2026, 11, 28, 21);
    expect(calendarWeekDays(today), hasLength(7));
    expect(calendarWeekDays(today).first, DateTime(2026, 11, 28));
    expect(calendarWeekDays(today).last, DateTime(2026, 12, 4));
    expect(calendarWeekPeriod(today), (
      start: DateTime(2026, 11, 28),
      end: DateTime(2026, 12, 5),
    ));
  });

  test('LabelsAndCodes', () {
    const andor = CalendarEntry(
      kind: CalendarEntryKind.series,
      title: 'Andor',
      count: 4,
    );
    const weapons = CalendarEntry(
      kind: CalendarEntryKind.movie,
      title: 'Weapons',
    );
    expect(calendarEntryLabel(andor, l), 'Andor ×4');
    expect(calendarEntryLabel(weapons, l), 'Weapons');
    expect(episodeCode(3, 4), 'S03E04');
    expect(episodeCode(3, 1, last: 3), 'S03E01–E03');
  });

  test('RoutesFollowTheTable', () {
    CalendarEntry entry(CalendarEntryKind kind, {String? id, int? tmdb}) =>
        CalendarEntry(kind: kind, title: 't', jellyfinId: id, tmdbId: tmdb);
    const s = CalendarEntryKind.series;
    const m = CalendarEntryKind.movie;
    expect(
      calendarEntryRoute(entry(s, id: 'abc'), canRequest: false),
      '/item/abc',
    );
    expect(
      calendarEntryRoute(entry(s, tmdb: 123), canRequest: true),
      '/tmdb/tv/123',
    );
    expect(calendarEntryRoute(entry(s, tmdb: 123), canRequest: false), isNull);
    expect(
      calendarEntryRoute(entry(m, id: 'def'), canRequest: false),
      '/item/def',
    );
    expect(
      calendarEntryRoute(entry(m, tmdb: 456), canRequest: true),
      '/tmdb/movie/456',
    );
    expect(calendarEntryRoute(entry(m, tmdb: 456), canRequest: false), isNull);
  });

  test('TitlesAreCapitalized', () {
    expect(calendarMonthTitle(DateTime(2026, 10), l), 'Ottobre 2026');
    expect(calendarDayTitle(DateTime(2026, 10, 22), l), 'Giovedì 22 ottobre');
  });
}
