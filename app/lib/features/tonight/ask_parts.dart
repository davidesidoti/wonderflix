import '../../l10n/gen/app_localizations.dart';
import 'tonight_logic.dart';

/// Chi parla: la finestra di Stasera (singolare) o la sala del Match (plurale).
enum AskVoice { tonight, match }

/// Le parole della frase che si possono cambiare.
enum AskSlot { type, duration, genre, rating }

/// Un pezzo della frase: testo fisso se [slot] è `null`, altrimenti una
/// parola che si cambia.
class AskPart {
  const AskPart(this.text, {this.slot});

  final String text;
  final AskSlot? slot;
}

/// "Stasera un film di qualsiasi durata, di ogni genere, brutto." a pezzi.
/// Con le serie la durata non c'è (vale solo per i film, spec §3.1).
List<AskPart> askParts(
    TonightFilters filters, AskVoice voice, AppLocalizations l) {
  final tonight = voice == AskVoice.tonight;
  final series = filters.type == TonightType.series;
  // Genere grammaticale e numero della parola del voto.
  final form = switch ((series, tonight)) {
    (false, true) => 'm',
    (true, true) => 'f',
    (false, false) => 'mp',
    (true, false) => 'fp',
  };
  final type = switch (filters.type) {
    TonightType.movies =>
      tonight ? l.askTypeTonightMovies : l.askTypeMatchMovies,
    TonightType.series =>
      tonight ? l.askTypeTonightSeries : l.askTypeMatchSeries,
    TonightType.both => tonight ? l.askTypeTonightBoth : l.askTypeMatchBoth,
  };
  final duration = switch (filters.duration) {
    TonightDuration.any => l.askDurationAny,
    TonightDuration.under90 => l.askDuration90,
    TonightDuration.under120 => l.askDuration120,
  };
  final genre = filters.genre;
  final rating = switch (filters.rating) {
    TonightRating.any => l.askRatingAny,
    TonightRating.good => l.askRatingGood(form),
    TonightRating.bad => l.askRatingBad(form),
  };
  return [
    AskPart(tonight ? l.askIntroTonight : l.askIntroMatch),
    AskPart(type, slot: AskSlot.type),
    if (series)
      const AskPart(', ')
    else ...[
      const AskPart(' '),
      AskPart(duration, slot: AskSlot.duration),
      const AskPart(', '),
    ],
    AskPart(genre == null ? l.askGenreAny : l.askGenre(genre),
        slot: AskSlot.genre),
    const AskPart(', '),
    AskPart(rating, slot: AskSlot.rating),
    const AskPart('.'),
  ];
}

/// La voce del menu di una parola, scritta per intero (spec §3.2). [value] è
/// il valore del filtro: un enum, o il genere (`null`: tutti i generi).
String askMenuLabel(AskSlot slot, Object? value, AppLocalizations l) =>
    switch ((slot, value)) {
      (AskSlot.type, TonightType.movies) => l.askMenuTypeMovies,
      (AskSlot.type, TonightType.series) => l.askMenuTypeSeries,
      (AskSlot.type, TonightType.both) => l.askMenuTypeBoth,
      (AskSlot.duration, TonightDuration.any) => l.askMenuDurationAny,
      (AskSlot.duration, TonightDuration.under90) => l.askMenuDuration90,
      (AskSlot.duration, TonightDuration.under120) => l.askMenuDuration120,
      (AskSlot.genre, null) => l.askMenuGenreAll,
      (AskSlot.genre, final String genre) => genre,
      (AskSlot.rating, TonightRating.any) => l.askMenuRatingAny,
      (AskSlot.rating, TonightRating.good) => l.askMenuRatingGood,
      (AskSlot.rating, TonightRating.bad) => l.askMenuRatingBad,
      _ => throw ArgumentError('$value non va con $slot'),
    };
