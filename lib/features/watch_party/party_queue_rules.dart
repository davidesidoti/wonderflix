import 'dart:math' as math;

import '../../core/jellyfin/item_models.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../library/item_labels.dart';

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
/// prossimo non cambia la posizione dell'elemento in riproduzione. Senza un
/// elemento in riproduzione (anche con l'indice oltre la fine) sono tutti
/// prossimi: l'indice è lo stesso.
int partyQueueMoveIndex(PlayQueue queue, int upcomingIndex) =>
    queue.playing == null
        ? upcomingIndex
        : queue.playingIndex + 1 + upcomingIndex;

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
/// ancora confermato dal server, se sono ancora gli stessi elementi (senza
/// ripetizioni); altrimenti come sono nella coda.
List<PlayQueueEntry> partyQueueInOrder(
    List<PlayQueueEntry> upcoming, List<String>? order) {
  if (order == null ||
      order.length != upcoming.length ||
      order.toSet().length != order.length) {
    return upcoming;
  }
  final byId = {for (final entry in upcoming) entry.playlistItemId: entry};
  final sorted = [for (final id in order) ?byId[id]];
  return sorted.length == upcoming.length ? sorted : upcoming;
}

/// Posto libero nella coda, sotto il tetto di [partyQueueLimit] (mai meno
/// di 0: una coda fatta da un altro client può essere più lunga).
int partyQueueRoom(PlayQueue queue) =>
    math.max(0, partyQueueLimit - queue.entries.length);

/// `ItemId` già in coda per un'aggiunta (spec H §8.2): l'elemento in
/// riproduzione e i prossimi. Un titolo già visto si può riaggiungere.
Set<String> partyQueueQueuedIds(PlayQueue queue) {
  final sections = partyQueueSections(queue);
  return {
    ?sections.playing?.itemId,
    for (final entry in sections.upcoming) entry.itemId,
  };
}

/// Cosa si manda per un'aggiunta (spec H §8.2).
class PartyQueueAddPlan {
  const PartyQueueAddPlan({
    required this.send,
    required this.alreadyQueued,
    required this.cut,
  });

  /// Gli id da mandare, nell'ordine dato.
  final List<String> send;

  /// Quanti erano già in coda (o in un'aggiunta ancora in attesa).
  final int alreadyQueued;

  /// Quanti restano fuori per il tetto.
  final int cut;
}

/// I candidati [itemIds], in ordine, senza quelli già in coda, quelli di
/// un'aggiunta ancora in attesa ([pending]) e i doppioni; poi tagliati al
/// posto libero.
PartyQueueAddPlan partyQueueAddPlan(PlayQueue queue, List<String> itemIds,
    {Set<String> pending = const {}}) {
  final queued = {...partyQueueQueuedIds(queue), ...pending};
  final fresh = <String>[];
  var alreadyQueued = 0;
  for (final id in itemIds) {
    if (queued.contains(id)) {
      alreadyQueued++;
    } else if (!fresh.contains(id)) {
      fresh.add(id);
    }
  }
  final send = fresh.take(partyQueueRoom(queue)).toList();
  return PartyQueueAddPlan(
    send: send,
    alreadyQueued: alreadyQueued,
    cut: fresh.length - send.length,
  );
}

/// Cosa dice un avviso di aggiunta (spec H §10): un titolo; oppure quanti
/// episodi di quale serie; oppure quanti titoli.
class PartyQueueAddition {
  const PartyQueueAddition({required this.count, this.title, this.series});

  final int count;

  /// Un titolo solo: il film, o "Dark · S1:E1".
  final String? title;

  /// Più episodi, tutti della stessa serie.
  final String? series;
}

/// [items]: i dettagli dei titoli aggiunti; [count]: quanti sono in tutto,
/// se i dettagli sono solo di una parte (allora si dice solo quanti).
PartyQueueAddition partyQueueAddition(List<JellyfinItem> items, {int? count}) {
  final total = count ?? items.length;
  if (items.length != total) return PartyQueueAddition(count: total);
  if (total == 1) {
    final item = items.single;
    final code = episodeCode(item);
    return PartyQueueAddition(
      count: 1,
      title: item.kind == ItemKind.episode && code != null
          ? '${cardTitle(item)} · $code'
          : cardTitle(item),
    );
  }
  final seriesIds = {
    for (final item in items) item.kind == ItemKind.episode ? item.seriesId : null,
  };
  final series = items.first.seriesName;
  if (seriesIds.length == 1 && seriesIds.single != null && series != null) {
    return PartyQueueAddition(count: total, series: series);
  }
  return PartyQueueAddition(count: total);
}
