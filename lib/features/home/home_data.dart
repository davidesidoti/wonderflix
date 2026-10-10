import '../../core/jellyfin/item_models.dart';

/// Come jellyfin-web: nei "Prossimi episodi" solo le serie guardate negli
/// ultimi 365 giorni.
DateTime nextUpCutoff(DateTime now) => now.subtract(const Duration(days: 365));

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
