import '../../core/jellyfin/item_models.dart';
import '../../core/social/collections_models.dart';

/// Ordinamenti della vista "Saghe" (spec K §8.4).
enum CollectionSort {
  /// Per `SortName`.
  name,

  /// Dalla saga con più film; a parità per nome.
  size,

  /// Dalla più recente; senza data in fondo, a parità per nome.
  dateAdded,
}

/// Lettere accentate e la loro forma semplice, per la ricerca.
const _plainLetters = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
  'ý': 'y', 'ÿ': 'y', 'ç': 'c', 'ñ': 'n',
};

/// Testo per i confronti della ricerca: minuscolo, senza accenti e senza
/// spazi ai lati (spec K §8.5).
String foldForSearch(String text) {
  final buffer = StringBuffer();
  for (final char in text.trim().toLowerCase().split('')) {
    buffer.write(_plainLetters[char] ?? char);
  }
  return buffer.toString();
}

/// Id di Jellyfin confrontabili: senza trattini e in minuscolo.
String collectionKey(String id) => id.replaceAll('-', '').toLowerCase();

int _byName(CollectionSummary a, CollectionSummary b) =>
    a.sortName.compareTo(b.sortName);

/// Le saghe di ogni titolo, per [collectionKey] dell'id: dalla più piccola
/// alla più grande, a parità per nome (spec K §8.3). La grandezza conta i
/// titoli distinti: un id ripetuto nell'elenco non fa pesare di più la saga.
Map<String, List<CollectionSummary>> indexCollections(
    List<CollectionSummary> collections) {
  final index = <String, List<CollectionSummary>>{};
  final sizes = <String, int>{};
  for (final collection in collections) {
    final keys = {for (final id in collection.itemIds) collectionKey(id)};
    sizes[collection.id] = keys.length;
    for (final key in keys) {
      final sagas = index.putIfAbsent(key, () => []);
      if (sagas.every((saga) => saga.id != collection.id)) sagas.add(collection);
    }
  }
  for (final sagas in index.values) {
    sagas.sort((a, b) {
      final bySize = sizes[a.id]!.compareTo(sizes[b.id]!);
      return bySize != 0 ? bySize : _byName(a, b);
    });
  }
  return index;
}

/// Le saghe il cui nome contiene [query] (confronto con [foldForSearch]);
/// tutte, con [query] vuota.
List<CollectionSummary> filterCollections(
    List<CollectionSummary> collections, String query) {
  final folded = foldForSearch(query);
  if (folded.isEmpty) return collections;
  return [
    for (final collection in collections)
      if (foldForSearch(collection.name).contains(folded)) collection,
  ];
}

/// Le saghe per la ricerca: al massimo [max], in ordine di nome; nessuna
/// con un testo vuoto (spec K §8.5).
List<CollectionSummary> matchCollections(
    List<CollectionSummary> collections, String term,
    {required int max}) {
  if (foldForSearch(term).isEmpty) return const [];
  final found = filterCollections(collections, term).toList()..sort(_byName);
  return found.take(max).toList();
}

/// [collections] in un elenco nuovo, ordinato per [sort].
List<CollectionSummary> sortCollections(
    List<CollectionSummary> collections, CollectionSort sort) {
  final int Function(CollectionSummary, CollectionSummary) compare =
      switch (sort) {
    CollectionSort.name => _byName,
    CollectionSort.size => (a, b) {
        final bySize = b.size.compareTo(a.size);
        return bySize != 0 ? bySize : _byName(a, b);
      },
    CollectionSort.dateAdded => (a, b) {
        final first = a.dateCreated;
        final second = b.dateCreated;
        if (first != null && second != null && first != second) {
          return second.compareTo(first);
        }
        if (first == null && second != null) return 1;
        if (first != null && second == null) return -1;
        return _byName(a, b);
      },
  };
  return collections.toList()..sort(compare);
}

/// Il titolo da proporre nella pagina di una saga (spec K §8.2): il primo,
/// in ordine di uscita, non ancora visto; se sono tutti visti, il primo.
/// `null` senza titoli.
JellyfinItem? sagaTarget(List<JellyfinItem> items,
    UserItemData Function(JellyfinItem item) userDataOf) {
  for (final item in items) {
    if (!userDataOf(item).played) return item;
  }
  return items.isEmpty ? null : items.first;
}

/// Quanti titoli di [items] sono visti.
int watchedCount(List<JellyfinItem> items,
        UserItemData Function(JellyfinItem item) userDataOf) =>
    items.where((item) => userDataOf(item).played).length;
