import 'package:flutter/foundation.dart';

import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';

/// Quanti titoli si pescano per volta (spec M §8.4).
const tonightBatch = 50;

/// Quante pescate al massimo per trovare un titolo nuovo, prima di dire che
/// non ce ne sono (decisione 6 del piano 19c).
const tonightMaxBatches = 3;

/// Quanti generi nella riga dei dati del titolo proposto.
const tonightMetaGenres = 3;

/// Il filtro del tipo (spec M §8.4); [wire] si salva nel profilo.
enum TonightType {
  movies('movies', {ItemKind.movie}),
  series('series', {ItemKind.series}),
  both('both', {ItemKind.movie, ItemKind.series});

  const TonightType(this.wire, this.kinds);

  final String wire;
  final Set<ItemKind> kinds;

  /// Un valore sconosciuto vale [both], il predefinito.
  static TonightType parse(String? raw) =>
      values.firstWhere((type) => type.wire == raw, orElse: () => both);
}

/// Il filtro della durata, solo per i film (spec M §8.4).
enum TonightDuration {
  any('any', null),
  under90('90', Duration(minutes: 90)),
  under120('120', Duration(minutes: 120));

  const TonightDuration(this.wire, this.limit);

  final String wire;

  /// Più corti di così; `null`: qualsiasi durata.
  final Duration? limit;

  static TonightDuration parse(String? raw) => values
      .firstWhere((duration) => duration.wire == raw, orElse: () => any);
}

/// Il filtro del voto della community di Jellyfin (0.16.1): i "belli" per
/// una serata sicura, i "brutti" per le serate trash.
enum TonightRating {
  any('any', null, null),
  good('good', 7, null),
  bad('bad', null, 5);

  const TonightRating(this.wire, this.min, this.max);

  final String wire;

  /// Voto minimo e massimo compresi; `null`: nessun limite.
  final double? min;
  final double? max;

  static TonightRating parse(String? raw) =>
      values.firstWhere((rating) => rating.wire == raw, orElse: () => any);
}

/// I filtri della finestra.
@immutable
class TonightFilters {
  const TonightFilters({
    this.type = TonightType.both,
    this.duration = TonightDuration.any,
    this.genre,
    this.rating = TonightRating.any,
  });

  static const defaults = TonightFilters();

  final TonightType type;
  final TonightDuration duration;

  /// `null`: tutti i generi.
  final String? genre;

  final TonightRating rating;

  bool get isDefault => this == defaults;

  static const _keep = Object();

  TonightFilters copyWith({
    TonightType? type,
    TonightDuration? duration,
    Object? genre = _keep,
    TonightRating? rating,
  }) =>
      TonightFilters(
        type: type ?? this.type,
        duration: duration ?? this.duration,
        genre: identical(genre, _keep) ? this.genre : genre as String?,
        rating: rating ?? this.rating,
      );

  @override
  bool operator ==(Object other) =>
      other is TonightFilters &&
      other.type == type &&
      other.duration == duration &&
      other.genre == genre &&
      other.rating == rating;

  @override
  int get hashCode => Object.hash(type, duration, genre, rating);

  @override
  String toString() => 'TonightFilters($type, $duration, $genre, $rating)';
}

/// Una serie mai iniziata: nessun episodio visto (decisione 3 del piano
/// 19c). Serve `RecursiveItemCount`, che `LibraryApi.randomUnplayed` chiede.
bool neverStarted(JellyfinItem series) {
  final episodes = series.recursiveItemCount;
  return !series.userData.played &&
      episodes != null &&
      episodes > 0 &&
      series.userData.unplayedItemCount == episodes;
}

/// Un titolo da proporre con [filters]: un film non visto e non iniziato (con
/// una posizione salvata sarebbe in "Continua a guardare") della durata
/// scelta, o una serie mai iniziata. La durata vale solo per i film; un film
/// senza durata nota non passa un filtro di durata (decisione 5), un titolo
/// senza voto non passa un filtro di voto.
bool tonightEligible(JellyfinItem item, TonightFilters filters) =>
    _rated(item.communityRating, filters.rating) &&
    switch (item.kind) {
      ItemKind.movie => filters.type != TonightType.series &&
          !item.userData.played &&
          item.userData.playbackPositionTicks == 0 &&
          _fits(item.runtime, filters.duration.limit),
      ItemKind.series =>
        filters.type != TonightType.movies && neverStarted(item),
      _ => false,
    };

bool _fits(Duration? runtime, Duration? limit) =>
    limit == null || (runtime != null && runtime < limit);

bool _rated(double? score, TonightRating rating) {
  final min = rating.min;
  final max = rating.max;
  if (min == null && max == null) return true;
  return score != null &&
      (min == null || score >= min) &&
      (max == null || score <= max);
}

/// "2024 · 2h 46m · Fantascienza · Avventura · Dramma"; per una serie le
/// stagioni al posto della durata.
String tonightMeta(AppLocalizations l, JellyfinItem item) {
  final runtime = item.runtime;
  final seasons = item.childCount;
  return [
    if (item.productionYear != null) '${item.productionYear}',
    if (item.kind == ItemKind.movie && runtime != null) formatRuntime(runtime),
    if (item.kind == ItemKind.series && seasons != null)
      l.detailSeasons(seasons),
    ...item.genres.take(tonightMetaGenres),
  ].join(' · ');
}

/// I generi del menu: di uno o due tipi, senza doppioni, in ordine
/// alfabetico (decisione 8 del piano 19c).
List<String> tonightGenreUnion(Iterable<List<String>> lists) =>
    {for (final list in lists) ...list}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
