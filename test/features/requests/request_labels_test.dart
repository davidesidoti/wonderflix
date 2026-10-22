import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/request_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/requests_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('stagioni in ordine, quelle di fila unite', () {
    expect(formatSeasonList(const []), '');
    expect(formatSeasonList(const [3]), '3');
    expect(formatSeasonList(const [2, 1]), '1–2');
    expect(formatSeasonList(const [5, 1, 2, 3, 3]), '1–3, 5');
  });

  test('testo dello stato', () {
    String label(RequestStatus status, [double? progress]) => requestStatusLabel(
        l, testMediaRequest(status: status, progress: progress));

    expect(label(RequestStatus.pending), 'In attesa');
    expect(label(RequestStatus.approved), 'Approvata');
    expect(label(RequestStatus.downloading, 0.456), 'In arrivo · 46%');
    expect(label(RequestStatus.downloading), 'In arrivo');
    expect(label(RequestStatus.partial), 'In parte disponibile');
    expect(label(RequestStatus.available), 'Disponibile');
    expect(label(RequestStatus.declined), 'Rifiutata');
    expect(label(RequestStatus.failed), 'Non riuscita');
  });

  test('colore dello stato', () {
    expect(requestStatusColor(RequestStatus.pending), WfColors.gold);
    expect(requestStatusColor(RequestStatus.downloading), WfColors.gold);
    expect(requestStatusColor(RequestStatus.approved), WfColors.cream);
    expect(requestStatusColor(RequestStatus.partial), WfColors.online);
    expect(requestStatusColor(RequestStatus.available), WfColors.online);
    expect(requestStatusColor(RequestStatus.declined), WfColors.error);
    expect(requestStatusColor(RequestStatus.failed), WfColors.error);
  });

  group('requestDateParts', () {
    setUpAll(() => initializeDateFormatting());
    final now = DateTime(2026, 10, 22, 12);
    List<(String, bool)> parts(MediaRequest r) =>
        [for (final p in requestDateParts(r, now, l)) (p.text, p.upcoming)];
    MediaRequest movie({
      DateTime? cinema,
      DateTime? digital,
      RequestStatus status = RequestStatus.approved,
    }) =>
        testMediaRequest(
            status: status, inCinemas: cinema, digitalRelease: digital);

    test('AwaitingReleaseHasItsLabelAndGold', () {
      expect(
          requestStatusLabel(
              l, testMediaRequest(status: RequestStatus.awaitingRelease)),
          "In attesa dell'uscita");
      expect(requestStatusColor(RequestStatus.awaitingRelease), WfColors.gold);
    });

    test('AMovieWaitingForDigital', () {
      expect(
          parts(movie(
              cinema: DateTime.utc(2026, 9, 25),
              digital: DateTime.utc(2026, 11, 12))),
          [
            ('Al cinema dal 25 settembre', false),
            ('in digitale previsto il 12 novembre', true),
          ]);
    });

    test('AMovieAlreadyOutDigitally', () {
      expect(
          parts(movie(
                  cinema: DateTime.utc(2026, 9, 25),
                  digital: DateTime.utc(2026, 10, 20)))
              .last,
          ('uscito in digitale il 20 ottobre', false));
    });

    test('AMovieWithoutDigitalDate', () {
      expect(parts(movie(cinema: DateTime.utc(2026, 12, 18))), [
        ('Al cinema dal 18 dicembre', true),
        ('in digitale: data non ancora nota', false),
      ]);
    });

    test('OnlyDigitalStartsUppercase', () {
      expect(parts(movie(digital: DateTime.utc(2026, 11, 12))),
          [('In digitale previsto il 12 novembre', true)]);
    });

    test('NoDatesNoLine', () {
      expect(parts(movie()), isEmpty);
    });

    test('FinishedMoviesHaveNoDates', () {
      expect(
          parts(movie(
              status: RequestStatus.available,
              cinema: DateTime.utc(2026, 9, 25),
              digital: DateTime.utc(2026, 11, 12))),
          isEmpty);
    });

    test('AnotherYearShowsTheYear', () {
      expect(parts(movie(digital: DateTime.utc(2027, 3, 31))).single.$1,
          'In digitale previsto il 31 marzo 2027');
    });

    test('AMovieDateIsTheUtcDay', () {
      // 23:30 UTC e' gia' il 13 in CET: il giorno deve restare quello UTC.
      final utc = DateTime.utc(2026, 11, 12, 23, 30);
      expect(parts(movie(digital: utc)).single.$1, contains('12 novembre'));
      expect(parts(movie(digital: utc.toLocal())).single.$1,
          contains('12 novembre'));
    });

    test('TodayIsNotUpcoming', () {
      expect(
          parts(movie(
              cinema: DateTime.utc(2026, 10, 22),
              digital: DateTime.utc(2026, 10, 22))),
          [
            ('Al cinema dal 22 ottobre', false),
            ('uscito in digitale il 22 ottobre', false),
          ]);
    });

    test('ASeriesDayIsTheLocalDay', () {
      final airing = DateTime.utc(2026, 11, 1, 23, 30);
      final local = airing.toLocal();
      final expected = DateFormat.MMMMd('it')
          .format(DateTime.utc(local.year, local.month, local.day));
      expect(
          parts(testMediaRequest(
              type: RequestMediaType.tv, nextAiring: airing)),
          [('Prossimo episodio il $expected', true)]);
    });

    test('ASeriesShowsItsNextEpisode', () {
      final airing = DateTime.utc(2026, 11, 2, 1);
      MediaRequest series({int? s, int? e, RequestStatus? st}) =>
          testMediaRequest(
              type: RequestMediaType.tv,
              status: st ?? RequestStatus.approved,
              nextAiring: airing,
              nextSeasonNumber: s,
              nextEpisodeNumber: e);
      expect(parts(series(s: 1, e: 4)),
          [('Prossimo episodio: S01E04 il 2 novembre', true)]);
      expect(parts(series()), [('Prossimo episodio il 2 novembre', true)]);
      expect(parts(series(st: RequestStatus.available)).length, 1);
    });

    test('APastNextAiringIsNotUpcoming', () {
      final airing = DateTime.utc(2026, 10, 20, 12);
      expect(
          parts(testMediaRequest(
              type: RequestMediaType.tv, nextAiring: airing)),
          [('Prossimo episodio il 20 ottobre', false)]);
    });
  });
}
