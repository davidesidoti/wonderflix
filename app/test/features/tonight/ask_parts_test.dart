import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/tonight/ask_parts.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  final en = lookupAppLocalizations(const Locale('en'));

  String text(TonightFilters f, AskVoice v, [AppLocalizations? loc]) =>
      askParts(f, v, loc ?? l).map((p) => p.text).join();

  test('la frase di Stasera, singolare', () {
    expect(
      text(
        const TonightFilters(
          type: TonightType.movies,
          rating: TonightRating.bad,
        ),
        AskVoice.tonight,
      ),
      'Stasera un film di qualsiasi durata, di ogni genere, brutto.',
    );
    expect(
      text(
        const TonightFilters(
          type: TonightType.series,
          duration: TonightDuration.under90,
          genre: 'Horror',
          rating: TonightRating.good,
        ),
        AskVoice.tonight,
      ),
      'Stasera una serie, di genere Horror, bella.',
    );
    expect(
      text(
        const TonightFilters(duration: TonightDuration.under120),
        AskVoice.tonight,
      ),
      'Stasera un film o una serie sotto le 2 ore, di ogni genere, '
      'con qualsiasi voto.',
    );
  });

  test('la frase di Match, plurale', () {
    expect(
      text(
        const TonightFilters(
          type: TonightType.series,
          rating: TonightRating.bad,
        ),
        AskVoice.match,
      ),
      'Si vota tra serie, di ogni genere, brutte.',
    );
    expect(
      text(
        const TonightFilters(
          type: TonightType.movies,
          duration: TonightDuration.under90,
          rating: TonightRating.good,
        ),
        AskVoice.match,
      ),
      'Si vota tra film sotto i 90 minuti, di ogni genere, belli.',
    );
    expect(
      text(
        const TonightFilters(
          type: TonightType.series,
          rating: TonightRating.good,
        ),
        AskVoice.match,
      ),
      'Si vota tra serie, di ogni genere, belle.',
    );
    expect(
      text(const TonightFilters(), AskVoice.match),
      'Si vota tra film e serie di qualsiasi durata, di ogni genere, '
      'con qualsiasi voto.',
    );
  });

  test('in inglese la stessa costruzione', () {
    expect(
      text(
        const TonightFilters(
          type: TonightType.movies,
          rating: TonightRating.bad,
        ),
        AskVoice.tonight,
        en,
      ),
      'Tonight a movie of any length, of any genre, rated badly.',
    );
  });

  test('tutte le combinazioni voce x tipo x voto', () {
    const expected = {
      'tonight/movies/any':
          'Stasera un film di qualsiasi durata, di ogni genere, con qualsiasi voto.',
      'tonight/movies/good':
          'Stasera un film di qualsiasi durata, di ogni genere, bello.',
      'tonight/movies/bad':
          'Stasera un film di qualsiasi durata, di ogni genere, brutto.',
      'tonight/series/any':
          'Stasera una serie, di ogni genere, con qualsiasi voto.',
      'tonight/series/good': 'Stasera una serie, di ogni genere, bella.',
      'tonight/series/bad': 'Stasera una serie, di ogni genere, brutta.',
      'tonight/both/any':
          'Stasera un film o una serie di qualsiasi durata, di ogni genere, con qualsiasi voto.',
      'tonight/both/good':
          'Stasera un film o una serie di qualsiasi durata, di ogni genere, bello.',
      'tonight/both/bad':
          'Stasera un film o una serie di qualsiasi durata, di ogni genere, brutto.',
      'match/movies/any':
          'Si vota tra film di qualsiasi durata, di ogni genere, con qualsiasi voto.',
      'match/movies/good':
          'Si vota tra film di qualsiasi durata, di ogni genere, belli.',
      'match/movies/bad':
          'Si vota tra film di qualsiasi durata, di ogni genere, brutti.',
      'match/series/any':
          'Si vota tra serie, di ogni genere, con qualsiasi voto.',
      'match/series/good': 'Si vota tra serie, di ogni genere, belle.',
      'match/series/bad': 'Si vota tra serie, di ogni genere, brutte.',
      'match/both/any':
          'Si vota tra film e serie di qualsiasi durata, di ogni genere, con qualsiasi voto.',
      'match/both/good':
          'Si vota tra film e serie di qualsiasi durata, di ogni genere, belli.',
      'match/both/bad':
          'Si vota tra film e serie di qualsiasi durata, di ogni genere, brutti.',
    };
    var cases = 0;
    for (final voice in AskVoice.values) {
      for (final type in TonightType.values) {
        for (final rating in TonightRating.values) {
          final key = '${voice.name}/${type.name}/${rating.name}';
          final filters = TonightFilters(type: type, rating: rating);
          expect(text(filters, voice), expected[key], reason: key);
          final english = text(filters, voice, en);
          if (rating == TonightRating.good) {
            expect(english, contains('rated well'));
          }
          if (rating == TonightRating.bad) {
            expect(english, contains('rated badly'));
          }
          cases++;
        }
      }
    }
    expect(cases, expected.length);
  });

  test('durata sotto i 90 minuti e genere nella voce del Match', () {
    expect(
      text(
        const TonightFilters(duration: TonightDuration.under90),
        AskVoice.match,
      ),
      'Si vota tra film e serie sotto i 90 minuti, di ogni genere, '
      'con qualsiasi voto.',
    );
    expect(
      text(
        const TonightFilters(
          type: TonightType.series,
          genre: 'Fantascienza',
          rating: TonightRating.good,
        ),
        AskVoice.match,
      ),
      'Si vota tra serie, di genere Fantascienza, belle.',
    );
  });

  test('le parole che si cambiano: niente durata con le serie', () {
    for (final voice in AskVoice.values) {
      final series = askParts(
        const TonightFilters(type: TonightType.series),
        voice,
        l,
      );
      expect(series.where((p) => p.slot == AskSlot.duration), isEmpty);
      expect(series.map((p) => p.slot).whereType<AskSlot>(), [
        AskSlot.type,
        AskSlot.genre,
        AskSlot.rating,
      ]);
      for (final type in [TonightType.movies, TonightType.both]) {
        final parts = askParts(TonightFilters(type: type), voice, l);
        expect(parts.map((p) => p.slot).whereType<AskSlot>(), AskSlot.values);
      }
    }
  });

  test('le voci del menu', () {
    expect(
      askMenuLabel(AskSlot.rating, TonightRating.bad, l),
      'Brutti (5 o meno)',
    );
    expect(
      askMenuLabel(AskSlot.rating, TonightRating.good, l),
      'Belli (7 o più)',
    );
    expect(
      askMenuLabel(AskSlot.rating, TonightRating.any, l),
      'Qualsiasi voto',
    );
    expect(askMenuLabel(AskSlot.type, TonightType.both, l), 'Film e serie');
    expect(askMenuLabel(AskSlot.type, TonightType.series, l), 'Serie');
    expect(
      askMenuLabel(AskSlot.duration, TonightDuration.under90, l),
      'Meno di 90 minuti',
    );
    expect(
      askMenuLabel(AskSlot.duration, TonightDuration.any, l),
      'Qualsiasi durata',
    );
    expect(askMenuLabel(AskSlot.genre, null, l), 'Tutti i generi');
    expect(askMenuLabel(AskSlot.genre, 'Horror', l), 'Horror');
  });
}
