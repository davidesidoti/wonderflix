import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';

/// Episodi al massimo nella coda di una serie: bastano per qualunque serata,
/// e una serie lunga non diventa una richiesta enorme.
const maxPartyQueue = 50;

/// Coda del gruppo per [item] (spec B §5.2): un film da solo; un episodio
/// con quelli che lo seguono nella serie, al massimo [maxPartyQueue].
Future<List<String>> buildPartyQueue(
    LibraryApi library, String userId, JellyfinItem item) async {
  final seriesId = item.seriesId;
  if (item.kind != ItemKind.episode || seriesId == null) return [item.id];
  final episodes = await library.episodesFrom(userId, seriesId, item.id,
      limit: maxPartyQueue);
  final ids = [for (final episode in episodes) episode.id];
  final start = ids.indexOf(item.id);
  return start < 0 ? [item.id] : ids.sublist(start);
}
