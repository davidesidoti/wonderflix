import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';
import '../../core/social/match_models.dart';
import '../watch_party/party_queue.dart';
import '../watch_party/party_queue_rules.dart';

/// Gli id del party di una sala, nell'ordine: [first] (se è un match o un
/// quasi match), altrimenti il primo match, altrimenti il primo quasi match;
/// poi gli altri match nell'ordine di uscita. I quasi match non scelti
/// restano fuori.
List<String> matchPartyOrder(MatchState state, {String? first}) {
  final nearIds = [for (final near in state.nearMatches) near.itemId];
  final head = first != null &&
          (state.matches.contains(first) || nearIds.contains(first))
      ? first
      : state.matches.firstOrNull ?? nearIds.firstOrNull;
  if (head == null) return const [];
  return [head, ...state.matches.where((id) => id != head)];
}

/// La coda del party per [titles] (già nell'ordine di [matchPartyOrder]): il
/// primo titolo come "Guarda insieme" (una serie dal primo episodio con
/// stagione >= 1, con i successivi), gli altri con un solo elemento. Una
/// serie senza episodi veri si salta; al massimo [partyQueueLimit] elementi.
Future<List<String>> buildMatchQueue(
    LibraryApi library, String userId, List<JellyfinItem> titles) async {
  final queue = <String>[];
  for (final title in titles) {
    if (queue.length >= partyQueueLimit) break;
    if (title.kind != ItemKind.series) {
      queue.add(title.id);
      continue;
    }
    final episodes = await library.allEpisodes(userId, title.id);
    if (episodes.isEmpty) continue;
    final start = episodes.indexWhere((e) => (e.parentIndexNumber ?? 0) >= 1);
    final from = episodes.sublist(start < 0 ? 0 : start);
    // Solo il primo titolo mette gli episodi successivi.
    final take = queue.isEmpty ? maxPartyQueue : 1;
    queue.addAll(from.take(take).map((e) => e.id));
  }
  return queue.take(partyQueueLimit).toList();
}
