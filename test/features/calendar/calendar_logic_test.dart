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

  test('MoviesComeFirstThenSeriesByTitle', () {
    final day = DateTime.utc(2026, 10, 22, 12);
    final map = entriesByDay(
      CalendarPage(
        episodes: [
          testEpisode(seriesName: 'B', airDate: day, tmdbId: 2),
          testEpisode(seriesName: 'a', airDate: day, tmdbId: 1),
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
    // il fuso non sposta mezzogiorno UTC.
    expect(day22.map((e) => e.title), ['A', 'b', 'a', 'B']);
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
