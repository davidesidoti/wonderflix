import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';

/// Filtri iniziali di La mia lista: film e serie dalla data di aggiunta,
/// l'ordine di sempre.
const myListInitialFilters = ItemQuery(
  kinds: {ItemKind.movie, ItemKind.series},
  sort: CatalogSort.dateAdded,
);

/// Cosa mostra La mia lista con i filtri scelti.
class MyListView {
  const MyListView({
    required this.items,
    required this.options,
    required this.listEmpty,
  });

  /// Titoli da mostrare, filtrati e ordinati.
  final List<JellyfinItem> items;

  /// Generi e anni da proporre nella barra dei filtri.
  final LibraryFilters options;

  /// Nessun titolo col cuore, prima dei filtri.
  final bool listEmpty;
}

/// Filtra e ordina nell'app i preferiti già caricati, come fa Jellyfin nel
/// catalogo. [overrides]: dati utente cambiati in questa sessione (cuore e
/// visto).
MyListView buildMyListView(
  List<JellyfinItem> items,
  ItemQuery filters,
  Map<String, UserItemData> overrides,
) {
  UserItemData userData(JellyfinItem item) =>
      overrides[item.id] ?? item.userData;
  // Tolti dal cuore in questa sessione: spariscono subito.
  final favorites = items.where((i) => userData(i).isFavorite).toList();
  final visible = favorites
      .where((i) => _matches(i, filters, played: userData(i).played))
      .toList()
    ..sort(_comparator(filters.sort));
  return MyListView(
    items: visible,
    options: _options(favorites, filters),
    listEmpty: favorites.isEmpty,
  );
}

bool _matches(JellyfinItem item, ItemQuery filters, {required bool played}) {
  if (filters.genres.isNotEmpty && !filters.genres.any(item.genres.contains)) {
    return false;
  }
  if (filters.year != null && item.productionYear != filters.year) return false;
  return switch (filters.watched) {
    WatchedFilter.all => true,
    WatchedFilter.unwatched => !played,
    WatchedFilter.watched => played,
  };
}

Comparator<JellyfinItem> _comparator(CatalogSort sort) => switch (sort) {
      CatalogSort.title => _byTitle,
      CatalogSort.dateAdded => _descending((i) => i.dateCreated),
      CatalogSort.year => _descending((i) => i.productionYear),
      CatalogSort.rating => _descending((i) => i.communityRating),
    };

/// `SortName` di Jellyfin (es. "matrix" per "The Matrix"), il nome se manca;
/// senza maiuscole.
String _titleKey(JellyfinItem item) =>
    (item.sortName ?? item.name).toLowerCase();

/// Per titolo; a parità per id, così l'ordine non cambia da un calcolo
/// all'altro.
int _byTitle(JellyfinItem a, JellyfinItem b) {
  final byKey = _titleKey(a).compareTo(_titleKey(b));
  return byKey != 0 ? byKey : a.id.compareTo(b.id);
}

/// Dal valore più alto; chi non ce l'ha va in fondo. A parità, per titolo.
Comparator<JellyfinItem> _descending(
        Comparable<Object>? Function(JellyfinItem item) value) =>
    (a, b) {
      final va = value(a);
      final vb = value(b);
      if (va == null || vb == null) {
        if (va != null) return -1;
        if (vb != null) return 1;
        return _byTitle(a, b);
      }
      final byValue = vb.compareTo(va);
      return byValue != 0 ? byValue : _byTitle(a, b);
    };

/// Generi e anni dei preferiti. La scelta attiva resta anche se nessun
/// titolo la ha più: il menu la mostra e la pagina dice che non c'è nulla.
LibraryFilters _options(List<JellyfinItem> favorites, ItemQuery filters) {
  final genres = {
    for (final item in favorites) ...item.genres,
    ...filters.genres,
  }.toList()
    ..sort((a, b) {
      final byLower = a.toLowerCase().compareTo(b.toLowerCase());
      return byLower != 0 ? byLower : a.compareTo(b);
    });
  final years = {
    for (final item in favorites) ?item.productionYear,
    ?filters.year,
  }.toList()
    ..sort((a, b) => b.compareTo(a));
  return LibraryFilters(genres: genres, years: years);
}
