import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/home/hero_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  final it = lookupAppLocalizations(const Locale('it'));
  final en = lookupAppLocalizations(const Locale('en'));
  final now = DateTime(2026, 11, 15, 22);

  JellyfinItem movie(String? created) =>
      testItem(dateCreated: created, kind: ItemKind.movie);

  group('heroArrivalLabel', () {
    test('oggi, ieri, giorno della settimana, data', () {
      expect(heroArrivalLabel(movie('2026-11-15T08:00:00'), now, it),
          'Film · arrivato oggi');
      expect(
          heroArrivalLabel(
              testItem(kind: ItemKind.series, dateCreated: '2026-11-14T23:00:00'),
              now,
              it),
          'Serie · arrivata ieri');
      expect(heroArrivalLabel(movie('2026-11-10T12:00:00'), now, it),
          'Film · arrivato martedì');
      expect(heroArrivalLabel(movie('2026-11-03T12:00:00'), now, it),
          'Film · arrivato il 3 novembre');
      expect(heroArrivalLabel(movie('2026-11-03T12:00:00'), now, en),
          'Movie · added on November 3');
    });

    test('senza data o per un episodio non c\'è etichetta', () {
      expect(heroArrivalLabel(movie(null), now, it), isNull);
      expect(
          heroArrivalLabel(
              testItem(kind: ItemKind.episode, dateCreated: '2026-11-15T08:00:00'),
              now,
              it),
          isNull);
    });
  });

  group('heroMeta', () {
    test('film: anno, durata, due generi tradotti', () {
      final item = testItem(
          year: 2026,
          runtimeMinutes: 157,
          genres: ['Science Fiction', 'Mystery', 'Drama']);
      expect(heroMeta(item, it), '2026 · 2h 37m · Fantascienza · Mistero');
    });

    test('serie: stagioni e Miniserie', () {
      final item = testItem(
          kind: ItemKind.series,
          year: 2025,
          childCount: 1,
          genres: ['Thriller', 'Mini-Series']);
      expect(heroMeta(item, it), '2025 · 1 stagione · Thriller · Miniserie');
    });

    test('generi che diventano uguali contano una volta', () {
      final item = testItem(
          year: null, runtimeMinutes: null, genres: ['Drama', 'Dramma']);
      expect(heroMeta(item, it), 'Dramma');
    });

    test('senza dati è vuota', () {
      expect(heroMeta(testItem(year: null, runtimeMinutes: null), it), '');
    });
  });
}
