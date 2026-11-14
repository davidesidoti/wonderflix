import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/genre_labels.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../library/library_providers.dart';
import 'catalog_controller.dart';

/// Un genere con i titoli che contiene.
class GenreCount {
  const GenreCount(this.label, this.count);

  final String label;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is GenreCount && other.label == label && other.count == count;

  @override
  int get hashCode => Object.hash(label, count);

  @override
  String toString() => 'GenreCount($label, $count)';
}

/// Sotto questa soglia un genere non ha una riga nel cartellone.
const minGenreCount = 5;

/// I generi di [kind] con almeno [minGenreCount] titoli, dal più fornito.
/// Resta in cache per la sessione e si rilegge quando cambia la libreria; un
/// errore no (si riprova al prossimo ascolto).
final catalogGenresProvider = FutureProvider.autoDispose
    .family<List<GenreCount>, ItemKind>((ref, kind) async {
  ref.watch(libraryRevisionProvider);
  final api = ref.watch(libraryApiProvider);
  final userId = ref.watch(currentUserIdProvider);
  final link = ref.keepAlive();
  try {
    final labels = (await ref.watch(catalogFiltersProvider(kind).future)).genres;
    final counts = await Future.wait([
      for (final label in labels)
        api
            .items(
                ItemQuery(
                    kinds: {kind}, genres: genreServerNames(label).toSet()),
                userId: userId,
                startIndex: 0,
                limit: 0)
            .then((page) => GenreCount(label, page.totalCount)),
    ]);
    return [
      for (final c in counts)
        if (c.count >= minGenreCount) c,
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });
  } on Object {
    link.close();
    rethrow;
  }
});

/// Totale dei titoli e il numero "secondario": film visti, serie in corso.
class CatalogTotals {
  const CatalogTotals(this.total, this.secondary);

  final int total;
  final int secondary;

  @override
  bool operator ==(Object other) =>
      other is CatalogTotals &&
      other.total == total &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(total, secondary);

  @override
  String toString() => 'CatalogTotals($total, $secondary)';
}

/// Totali di un tipo, di tutto il catalogo (genere null) o di un genere.
final catalogTotalsProvider = FutureProvider.autoDispose
    .family<CatalogTotals, (ItemKind, String?)>((ref, key) async {
  ref.watch(libraryRevisionProvider);
  final api = ref.watch(libraryApiProvider);
  final userId = ref.watch(currentUserIdProvider);
  final (kind, genre) = key;
  final link = ref.keepAlive();
  try {
    final base = ItemQuery(
        kinds: {kind},
        genres: genre == null ? const {} : genreServerNames(genre).toSet());
    final secondaryQuery = kind == ItemKind.series
        ? base.copyWith(seriesStatus: SeriesStatusFilter.continuing)
        : base.copyWith(watched: WatchedFilter.watched);
    Future<int> count(ItemQuery q) async =>
        (await api.items(q, userId: userId, startIndex: 0, limit: 0))
            .totalCount;
    final (total, secondary) = await (count(base), count(secondaryQuery)).wait;
    return CatalogTotals(total, secondary);
  } on Object {
    link.close();
    rethrow;
  }
});
