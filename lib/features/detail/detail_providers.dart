import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';
import '../library/library_providers.dart';

final itemProvider =
    FutureProvider.autoDispose.family<JellyfinItem, String>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(libraryApiProvider).item(ref.watch(currentUserIdProvider), id);
});

final similarProvider =
    FutureProvider.autoDispose.family<List<JellyfinItem>, String>((ref, id) =>
        ref.watch(libraryApiProvider).similar(ref.watch(currentUserIdProvider), id));

final seasonsProvider =
    FutureProvider.autoDispose.family<List<JellyfinItem>, String>((ref, seriesId) {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(libraryApiProvider)
      .seasons(ref.watch(currentUserIdProvider), seriesId);
});

final episodesProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, ({String seriesId, String seasonId})>((ref, key) {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(libraryApiProvider)
      .episodes(ref.watch(currentUserIdProvider), key.seriesId, key.seasonId);
});

/// Episodio da proporre per una serie: il prossimo (o quello iniziato),
/// oppure il primo della prima stagione.
Future<JellyfinItem?> findNextEpisode(
    LibraryApi api, String userId, String seriesId) async {
  final next = await api.nextUp(userId,
      seriesId: seriesId, limit: 1, enableResumable: true);
  if (next.isNotEmpty) return next.first;
  final seasons = await api.seasons(userId, seriesId);
  final regular = seasons.where((s) => (s.indexNumber ?? 0) > 0);
  final first = regular.isNotEmpty ? regular.first : seasons.firstOrNull;
  if (first == null) return null;
  final episodes = await api.episodes(userId, seriesId, first.id);
  return episodes.firstOrNull;
}

final seriesNextEpisodeProvider = FutureProvider.autoDispose
    .family<JellyfinItem?, String>((ref, seriesId) {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  return findNextEpisode(
      ref.watch(libraryApiProvider), ref.watch(currentUserIdProvider), seriesId);
});
