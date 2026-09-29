import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../core/jellyfin/library_api.dart';
import '../library/library_providers.dart';

class HomeData {
  const HomeData({
    required this.featured,
    required this.resume,
    required this.nextUp,
    required this.latestMovies,
    required this.latestSeries,
    required this.favorites,
  });

  final List<JellyfinItem> featured;
  final List<JellyfinItem> resume;
  final List<JellyfinItem> nextUp;
  final List<JellyfinItem> latestMovies;
  final List<JellyfinItem> latestSeries;
  final List<JellyfinItem> favorites;

  bool get isEmpty =>
      resume.isEmpty &&
      nextUp.isEmpty &&
      latestMovies.isEmpty &&
      latestSeries.isEmpty &&
      favorites.isEmpty;
}

/// Come jellyfin-web: nei "Prossimi episodi" solo le serie guardate negli
/// ultimi 365 giorni.
DateTime nextUpCutoff(DateTime now) => now.subtract(const Duration(days: 365));

/// Carica tutte le righe della Home in parallelo.
Future<HomeData> loadHome(LibraryApi api, String userId) async {
  Future<List<JellyfinItem>> latest(ItemQuery query) async =>
      (await api.items(query, userId: userId, startIndex: 0, limit: 20)).items;

  final results = await Future.wait<List<JellyfinItem>>([
    api.resume(userId, limit: 20),
    api.nextUp(userId, limit: 20, dateCutoff: nextUpCutoff(DateTime.now())),
    latest(const ItemQuery(kinds: {ItemKind.movie}, sort: CatalogSort.dateAdded)),
    latest(const ItemQuery(kinds: {ItemKind.series}, sort: CatalogSort.dateAdded)),
    latest(const ItemQuery(
      kinds: {ItemKind.movie, ItemKind.series},
      sort: CatalogSort.dateAdded,
      favoritesOnly: true,
    )),
  ]);
  return HomeData(
    featured: pickFeatured(results[2], results[3]),
    resume: results[0],
    nextUp: results[1],
    latestMovies: results[2],
    latestSeries: results[3],
    favorites: results[4],
  );
}

/// Fino a [max] titoli recenti con uno sfondo, alternando film e serie.
List<JellyfinItem> pickFeatured(
  List<JellyfinItem> movies,
  List<JellyfinItem> series, {
  int max = 5,
}) {
  final withBackdrop = [movies, series]
      .map((list) => list.where((i) => i.backdropTags.isNotEmpty).toList())
      .toList();
  final featured = <JellyfinItem>[];
  for (var i = 0; featured.length < max; i++) {
    var added = false;
    for (final list in withBackdrop) {
      if (i < list.length && featured.length < max) {
        featured.add(list[i]);
        added = true;
      }
    }
    if (!added) break;
  }
  return featured;
}

final homeProvider = FutureProvider.autoDispose<HomeData>((ref) {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  return loadHome(ref.watch(libraryApiProvider), ref.watch(currentUserIdProvider));
});
