import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_sections.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';

void main() {

  // Descrizione compatta: "T[a,b]" Stasera, "U[a,b]" In arrivo, "R:x" riga.
  List<String> shape(List<HomeRowKind> visible) => [
        for (final s in homeSections(visible))
          switch (s) {
            RowSection() => 'R:${s.kind.id}',
            TonightSection() => 'T[${s.rows.map((e) => e.id).join(',')}]',
            UpcomingSection() => 'U[${s.rows.map((e) => e.id).join(',')}]',
          },
      ];

  group('homeSections', () {
    test('Stasera sta al posto della prima delle sue righe', () {
      expect(
          shape([
            HomeRowKind.resume,
            HomeRowKind.recommended,
            HomeRowKind.nextUp,
            HomeRowKind.latestMovies,
          ]),
          ['T[resume,nextUp]', 'R:recommended', 'R:latestMovies']);
      expect(
          shape([
            HomeRowKind.recommended,
            HomeRowKind.nextUp,
            HomeRowKind.resume,
          ]),
          ['R:recommended', 'T[nextUp,resume]']);
    });

    test('basta una riga per avere la sezione', () {
      expect(shape([HomeRowKind.nextUp]), ['T[nextUp]']);
    });

    test('In arrivo unisce serie e film', () {
      expect(
          shape([
            HomeRowKind.upcomingMovies,
            HomeRowKind.myList,
            HomeRowKind.upcomingSeries,
          ]),
          ['U[upcomingMovies,upcomingSeries]', 'R:myList']);
    });

    test('senza nessuna delle quattro restano solo righe', () {
      expect(shape([HomeRowKind.latestSeries, HomeRowKind.myList]),
          ['R:latestSeries', 'R:myList']);
    });
  });

  group('tonightTickets', () {
    JellyfinItem ep(String id, String series, int e) => testItem(
        id: id,
        kind: ItemKind.episode,
        seriesId: series,
        seriesName: series,
        seasonIndex: 1,
        index: e);

    test('prima i resume, poi i nextUp di serie senza biglietto', () {
      final tickets = tonightTickets(
        resume: [ep('vq8', 'v', 8), testItem(id: 'hope', name: 'Hope')],
        nextUp: [ep('vq9', 'v', 9), ep('loki1', 'loki', 1)],
      );
      expect([for (final t in tickets) t.item.id], ['vq8', 'hope', 'loki1']);
      expect([for (final t in tickets) t.resumed], [true, true, false]);
    });

    test('un nextUp con lo stesso id di un resume una volta sola', () {
      final tickets = tonightTickets(
        resume: [testItem(id: 'x')],
        nextUp: [testItem(id: 'x')],
      );
      expect(tickets, hasLength(1));
      expect(tickets.single.resumed, isTrue);
    });
  });

  group('upcomingDays', () {
    UpcomingEpisode episode(DateTime at, int number) => UpcomingEpisode(
        seriesName: 'S',
        seasonNumber: 1,
        episodeNumber: number,
        airDate: at);
    UpcomingMovie movie(String title, DateTime at) =>
        UpcomingMovie(title: title, tmdbId: 1, digitalRelease: at);

    test('giorni in ordine, voci nell\'ordine di arrivo', () {
      final days = upcomingDays(
        episodes: [
          episode(DateTime(2026, 11, 18, 12), 1),
          episode(DateTime(2026, 11, 20, 12), 2),
          episode(DateTime(2026, 11, 20, 18), 3),
        ],
        movies: [
          movie('b', DateTime.utc(2026, 11, 23)),
          movie('a', DateTime.utc(2026, 11, 17)),
        ],
      );
      expect([for (final d in days) d.day.day], [17, 18, 20, 23]);
      final twenty = days[2].entries;
      expect([
        for (final e in twenty) (e as UpcomingEpisodeEntry).episode.episodeNumber
      ], [2, 3]);
      expect(((days[0].entries.single) as UpcomingMovieEntry).movie.title, 'a');
      expect(days[0].day, DateTime(2026, 11, 17));
    });
  });

  group('upcomingEpisodeCode', () {
    UpcomingEpisode e(int s, int n, [int? last]) => UpcomingEpisode(
        seriesName: 'S',
        seasonNumber: s,
        episodeNumber: n,
        lastEpisodeNumber: last,
        airDate: DateTime.utc(2026, 11, 18));

    test('singolo e gruppo', () {
      expect(upcomingEpisodeCode(e(2, 8)), 'S2:E8');
      expect(upcomingEpisodeCode(e(2, 8, 10)), 'S2:E8–E10');
      expect(upcomingEpisodeCode(e(23, 6)), 'S23:E6');
    });
  });

  group('upcomingDayNote', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final now = DateTime(2026, 11, 15, 22);

    test('oggi, domani, dopodomani, poi niente', () {
      expect(upcomingDayNote(DateTime(2026, 11, 15), now, it), 'oggi');
      expect(upcomingDayNote(DateTime(2026, 11, 14), now, it), 'oggi');
      expect(upcomingDayNote(DateTime(2026, 11, 16), now, it), 'domani');
      expect(upcomingDayNote(DateTime(2026, 11, 17), now, it), 'dopodomani');
      expect(upcomingDayNote(DateTime(2026, 11, 18), now, it), isNull);
    });
  });

  group('remainingMinutes', () {
    test('minuti che mancano, almeno 1; niente senza posizione o durata', () {
      expect(
          remainingMinutes(testItem(
              runtimeMinutes: 60, positionTicks: 450 * 10000000)),
          53);
      expect(
          remainingMinutes(testItem(
              runtimeMinutes: 60, positionTicks: 3590 * 10000000)),
          1);
      expect(remainingMinutes(testItem(runtimeMinutes: 60)), isNull);
      expect(
          remainingMinutes(
              testItem(runtimeMinutes: null, positionTicks: 450 * 10000000)),
          isNull);
    });
  });
}
