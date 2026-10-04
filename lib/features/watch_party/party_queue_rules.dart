import '../../core/jellyfin/item_models.dart';
import '../../core/syncplay/syncplay_models.dart';

/// Al massimo questi titoli in tutta la coda del gruppo (spec H §4). La coda
/// iniziale di una serie resta di `maxPartyQueue` (`party_queue.dart`).
const partyQueueLimit = 100;

/// La coda divisa come nel pannello "Coda" (spec H §9.2).
class PartyQueueSections {
  const PartyQueueSections({
    required this.watched,
    required this.playing,
    required this.upcoming,
  });

  /// Gli elementi prima di quello in riproduzione.
  final List<PlayQueueEntry> watched;
  final PlayQueueEntry? playing;

  /// Gli elementi dopo quello in riproduzione (tutti, se non ce n'è uno).
  final List<PlayQueueEntry> upcoming;
}

PartyQueueSections partyQueueSections(PlayQueue queue) {
  final playing = queue.playing;
  if (playing == null) {
    return PartyQueueSections(
        watched: const [], playing: null, upcoming: queue.entries);
  }
  return PartyQueueSections(
    watched: queue.entries.sublist(0, queue.playingIndex),
    playing: playing,
    upcoming: queue.entries.sublist(queue.playingIndex + 1),
  );
}

/// `NewIndex` di `MovePlaylistItem` per un prossimo portato alla posizione
/// [upcomingIndex] tra i prossimi (contata dopo averlo tolto). Spostare un
/// prossimo non cambia la posizione dell'elemento in riproduzione.
int partyQueueMoveIndex(PlayQueue queue, int upcomingIndex) =>
    queue.playingIndex + 1 + upcomingIndex;

/// Durata dei prossimi dai dettagli [items] (per `ItemId`); quelli senza
/// durata, o non ancora noti, non contano. `null` se nessuno ne ha una.
Duration? partyQueueUpcomingRuntime(
    PlayQueue queue, Map<String, JellyfinItem?> items) {
  Duration? total;
  for (final entry in partyQueueSections(queue).upcoming) {
    final runtime = items[entry.itemId]?.runtime;
    if (runtime != null) total = (total ?? Duration.zero) + runtime;
  }
  return total;
}

/// I prossimi nell'ordine [order] (id nella coda) di un trascinamento non
/// ancora confermato dal server, se sono ancora gli stessi elementi;
/// altrimenti come sono nella coda.
List<PlayQueueEntry> partyQueueInOrder(
    List<PlayQueueEntry> upcoming, List<String>? order) {
  if (order == null || order.length != upcoming.length) return upcoming;
  final byId = {for (final entry in upcoming) entry.playlistItemId: entry};
  final sorted = [for (final id in order) ?byId[id]];
  return sorted.length == upcoming.length ? sorted : upcoming;
}
