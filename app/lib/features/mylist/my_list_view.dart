import '../../core/jellyfin/genre_labels.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../core/jellyfin/json_fields.dart';
import '../catalog/catalog_genres.dart';

/// Scheda di La mia lista.
enum MyListTab {
  all,
  movies,
  series;

  /// Dal parametro `kind` dell'indirizzo; sconosciuto o assente: [all].
  static MyListTab parse(String? raw) => switch (raw) {
        'movies' => movies,
        'series' => series,
        _ => all,
      };
}

/// Dove sta un titolo della lista (spec §6.1).
enum MyListGroup { resume, start, watched }

/// Con più preferiti di così (tutte le schede) compaiono generi e ricerca.
const myListRefinementsThreshold = 24;

/// Spec §6.1. Film: visto se `played`, da continuare se ha un punto di
/// ripresa, altrimenti da iniziare. Serie: vista se non restano episodi da
/// vedere; da continuare se ne ha visti (`playedPercentage`, o senza di lui
/// meno episodi da vedere che nella serie); da iniziare negli altri casi, anche senza
/// conteggi.
MyListGroup myListGroup(JellyfinItem item, UserItemData data) {
  if (item.kind != ItemKind.series) {
    if (data.played) return MyListGroup.watched;
    return data.playbackPositionTicks > 0
        ? MyListGroup.resume
        : MyListGroup.start;
  }
  final unplayed = data.unplayedItemCount;
  if (unplayed == null) return MyListGroup.start;
  if (unplayed == 0) return MyListGroup.watched;
  final total = item.recursiveItemCount;
  final percentage = data.playedPercentage;
  // I conteggi decidono solo senza playedPercentage: 0 vuol dire mai vista.
  final started = percentage != null
      ? percentage > 0
      : (total != null && unplayed < total);
  return started ? MyListGroup.resume : MyListGroup.start;
}

const _keep = Object();

/// Ordine, genere e ricerca scelti nella pagina.
class MyListFilters {
  const MyListFilters({
    this.sort = CatalogSort.dateAdded,
    this.reversed = false,
    this.genre,
    this.search = '',
  });

  final CatalogSort sort;

  /// Inverte la chiave principale rispetto al verso di default.
  final bool reversed;

  /// Etichetta (`genreLabel`) o nessun genere.
  final String? genre;
  final String search;

  bool get hasRefinements => genre != null || search.trim().isNotEmpty;

  MyListFilters copyWith({
    CatalogSort? sort,
    bool? reversed,
    Object? genre = _keep,
    String? search,
  }) =>
      MyListFilters(
        sort: sort ?? this.sort,
        reversed: reversed ?? this.reversed,
        genre: identical(genre, _keep) ? this.genre : genre as String?,
        search: search ?? this.search,
      );
}

/// Cosa mostra La mia lista con la scheda e i filtri scelti.
class MyListView {
  const MyListView({
    required this.hero,
    required this.resume,
    required this.start,
    required this.watched,
    required this.tabCount,
    required this.resumeCount,
    required this.startCount,
    required this.watchedCount,
    required this.genres,
    required this.showRefinements,
    required this.listEmpty,
    required this.removableWatched,
    required this.noResults,
  });

  /// Titolo di punta della scheda intera (genere e ricerca non lo toccano).
  final JellyfinItem? hero;

  /// Gruppi con genere e ricerca applicati, ordinati, senza [hero].
  final List<JellyfinItem> resume, start, watched;

  /// Titoli della scheda e dei suoi gruppi, [hero] compreso.
  final int tabCount, resumeCount, startCount, watchedCount;

  /// Generi della scheda, per conteggio e poi per nome.
  final List<GenreCount> genres;

  /// Più di [myListRefinementsThreshold] preferiti, tutte le schede.
  final bool showRefinements;

  /// Nessun titolo col cuore, prima della scheda e dei filtri.
  final bool listEmpty;

  /// [watched] senza le serie in corso: una serie che esce ancora tornerebbe
  /// tra i titoli da continuare.
  final List<JellyfinItem> removableWatched;

  /// Genere e ricerca non lasciano nessun titolo della scheda ([hero]
  /// compreso).
  final bool noResults;
}

/// Filtra e ordina nell'app i preferiti già caricati; genere e ricerca di
/// [filters] valgono solo con `showRefinements`. [overrides]: dati
/// utente cambiati in questa sessione (cuore e visto). [added]: date di
/// aggiunta alla lista, con le chiavi di `jellyfinIdKey`.
MyListView buildMyListView(
  List<JellyfinItem> items,
  MyListTab tab,
  MyListFilters filters,
  Map<String, UserItemData> overrides,
  Map<String, DateTime> added,
) {
  UserItemData userData(JellyfinItem item) =>
      overrides[item.id] ?? item.userData;
  // Tolti dal cuore in questa sessione: spariscono subito.
  final favorites = items.where((i) => userData(i).isFavorite).toList();
  final showRefinements = favorites.length > myListRefinementsThreshold;
  // Senza la riga dei generi e il campo di ricerca non si filtra: un filtro
  // rimasto acceso nasconderebbe titoli senza modo di toglierlo.
  final refine = showRefinements
      ? filters
      : filters.copyWith(genre: null, search: '');
  final inTab = favorites
      .where((i) => switch (tab) {
            MyListTab.all => true,
            MyListTab.movies => i.kind == ItemKind.movie,
            MyListTab.series => i.kind == ItemKind.series,
          })
      .toList()
    ..sort(_comparator(filters, added));
  final groups = {
    for (final i in inTab) i: myListGroup(i, userData(i)),
  };
  List<JellyfinItem> of(MyListGroup g) =>
      [for (final i in inTab) if (groups[i] == g) i];
  final allResume = of(MyListGroup.resume);
  final allStart = of(MyListGroup.start);
  final allWatched = of(MyListGroup.watched);

  // Il titolo di punta ignora genere e ricerca: è della scheda intera.
  final hero = allResume.isNotEmpty
      ? allResume.first
      : allStart.isNotEmpty
          ? allStart.first
          : null;
  final search = refine.search.trim().toLowerCase();
  bool passes(JellyfinItem i) =>
      (refine.genre == null ||
          i.genres.any((g) => genreLabel(g) == refine.genre)) &&
      i.name.toLowerCase().contains(search);
  List<JellyfinItem> shown(List<JellyfinItem> group) =>
      [for (final i in group) if (i != hero && passes(i)) i];
  final watched = shown(allWatched);

  final counts = <String, int>{};
  for (final i in inTab) {
    for (final label in {for (final g in i.genres) genreLabel(g)}) {
      counts[label] = (counts[label] ?? 0) + 1;
    }
  }
  final genres = [
    for (final e in counts.entries) GenreCount(e.key, e.value),
  ]..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.label.compareTo(b.label);
    });

  return MyListView(
    hero: hero,
    resume: shown(allResume),
    start: shown(allStart),
    watched: watched,
    tabCount: inTab.length,
    resumeCount: allResume.length,
    startCount: allStart.length,
    watchedCount: allWatched.length,
    genres: genres,
    showRefinements: showRefinements,
    listEmpty: favorites.isEmpty,
    removableWatched: [
      for (final i in watched)
        if (i.status != 'Continuing') i
    ],
    noResults: refine.hasRefinements && !inTab.any(passes),
  );
}

/// Ordine scelto. Il verso di default è decrescente (Aggiunti, Anno, Voto) o
/// A→Z (Titolo); `reversed` inverte la chiave principale, a parità vale
/// sempre il titolo A→Z. Chi non ha anno o voto resta in fondo.
Comparator<JellyfinItem> _comparator(
    MyListFilters filters, Map<String, DateTime> added) {
  final sign = filters.reversed ? -1 : 1;
  int byAdded(JellyfinItem a, JellyfinItem b) {
    final da = added[jellyfinIdKey(a.id)];
    final db = added[jellyfinIdKey(b.id)];
    if (da != null && db != null) return db.compareTo(da);
    if (da != null) return -1;
    if (db != null) return 1;
    return _valued(a.dateCreated, b.dateCreated, 1);
  }

  return (a, b) {
    final primary = switch (filters.sort) {
      CatalogSort.title => sign * _titleKey(a).compareTo(_titleKey(b)),
      CatalogSort.dateAdded => sign * byAdded(a, b),
      CatalogSort.year => _valued(a.productionYear, b.productionYear, sign),
      CatalogSort.rating =>
        _valued(a.communityRating, b.communityRating, sign),
    };
    return primary != 0 ? primary : _byTitle(a, b);
  };
}

/// Dal valore più alto ([sign] 1) o più basso (-1); chi non ce l'ha in fondo.
int _valued<T extends Comparable<T>>(T? a, T? b, int sign) {
  if (a == null || b == null) return a != null ? -1 : (b != null ? 1 : 0);
  return sign * b.compareTo(a);
}

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
