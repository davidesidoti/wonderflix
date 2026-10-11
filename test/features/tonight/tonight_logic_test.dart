import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  JellyfinItem series({int? episodes, int? unplayed, bool played = false}) =>
      testItem(
          id: 's',
          kind: ItemKind.series,
          recursiveCount: episodes,
          unplayedCount: unplayed,
          played: played);

  test('i valori salvati, e quelli sconosciuti valgono il predefinito', () {
    expect(TonightType.parse('series'), TonightType.series);
    expect(TonightType.parse(null), TonightType.both);
    expect(TonightType.parse('boh'), TonightType.both);
    expect(TonightDuration.parse('90'), TonightDuration.under90);
    expect(TonightDuration.parse('120'), TonightDuration.under120);
    expect(TonightDuration.parse(null), TonightDuration.any);
    expect(TonightType.both.kinds, {ItemKind.movie, ItemKind.series});
  });

  test('ogni valore si salva e si rilegge uguale', () {
    for (final type in TonightType.values) {
      expect(TonightType.parse(type.wire), type);
    }
    for (final duration in TonightDuration.values) {
      expect(TonightDuration.parse(duration.wire), duration);
    }
    expect(TonightType.parse('movies'), TonightType.movies);
    expect(TonightType.parse('both'), TonightType.both);
    expect(TonightType.parse(''), TonightType.both);
    expect(TonightDuration.parse('any'), TonightDuration.any);
    expect(TonightDuration.parse('boh'), TonightDuration.any);
    expect(TonightDuration.parse(''), TonightDuration.any);
  });

  test('i filtri: predefiniti e copia', () {
    expect(TonightFilters.defaults.isDefault, isTrue);
    const drama = TonightFilters(genre: 'Dramma');
    expect(drama.isDefault, isFalse);
    expect(drama.copyWith(genre: null), TonightFilters.defaults);
    expect(drama.copyWith(type: TonightType.movies).genre, 'Dramma');
  });

  test('serie mai iniziata: tanti episodi da vedere quanti ne ha', () {
    expect(neverStarted(series(episodes: 40, unplayed: 40)), isTrue);
    expect(neverStarted(series(episodes: 8, unplayed: 5)), isFalse);
    expect(neverStarted(series(unplayed: 17)), isFalse,
        reason: 'senza RecursiveItemCount non si sa');
    expect(neverStarted(series(episodes: 0, unplayed: 0)), isFalse);
    expect(neverStarted(series(episodes: 4, unplayed: 4, played: true)),
        isFalse);
  });

  test('film: non visti e della durata scelta', () {
    const any = TonightFilters();
    const short = TonightFilters(duration: TonightDuration.under90);
    expect(tonightEligible(testItem(runtimeMinutes: 120), any), isTrue);
    expect(tonightEligible(testItem(runtimeMinutes: 120, played: true), any),
        isFalse);
    expect(tonightEligible(testItem(runtimeMinutes: 89), short), isTrue);
    expect(tonightEligible(testItem(runtimeMinutes: 90), short), isFalse);
    expect(tonightEligible(testItem(runtimeMinutes: null), short), isFalse,
        reason: 'durata sconosciuta');
    expect(
        tonightEligible(testItem(runtimeMinutes: 110),
            const TonightFilters(duration: TonightDuration.under120)),
        isTrue);
  });

  test('un film già iniziato non si propone: è in "Continua a guardare"', () {
    const any = TonightFilters();
    expect(
        tonightEligible(testItem(runtimeMinutes: 100, positionTicks: 0), any),
        isTrue);
    expect(
        tonightEligible(
            testItem(runtimeMinutes: 100, positionTicks: 600000000), any),
        isFalse);
    expect(
        tonightEligible(
            testItem(runtimeMinutes: 100, positionTicks: 600000000),
            const TonightFilters(duration: TonightDuration.under120)),
        isFalse);
  });

  test('il tipo, e la durata che vale solo per i film', () {
    final movie = testItem(runtimeMinutes: 150);
    final fresh = series(episodes: 10, unplayed: 10);
    expect(
        tonightEligible(movie, const TonightFilters(type: TonightType.series)),
        isFalse);
    expect(
        tonightEligible(fresh, const TonightFilters(type: TonightType.movies)),
        isFalse);
    expect(
        tonightEligible(
            fresh, const TonightFilters(duration: TonightDuration.under90)),
        isTrue);
    expect(tonightEligible(testItem(kind: ItemKind.episode), const TonightFilters()),
        isFalse);
  });

  test('la riga dei dati', () {
    expect(
        tonightMeta(
            l,
            testItem(
                year: 2024,
                runtimeMinutes: 166,
                genres: ['Fantascienza', 'Avventura', 'Dramma', 'Azione'])),
        '2024 · 2h 46m · Fantascienza · Avventura · Dramma');
    expect(
        tonightMeta(
            l,
            testItem(
                kind: ItemKind.series,
                year: 2016,
                runtimeMinutes: 55,
                childCount: 3,
                genres: ['Dramma'])),
        '2016 · 3 stagioni · Dramma');
  });

  test('i generi: unione senza doppioni, in ordine', () {
    expect(
        tonightGenreUnion([
          ['Dramma', 'Azione'],
          ['Dramma', 'Anime'],
        ]),
        ['Anime', 'Azione', 'Dramma']);
  });
}
