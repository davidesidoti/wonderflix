import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../library/library_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Dettagli dei titoli nella coda del gruppo (spec H §8.5), per `ItemId`:
/// assente = in arrivo, `null` = non disponibile (cancellato, o non più
/// visibile). Gli id nuovi si chiedono con `itemsByIds`, [fetchChunk] alla
/// volta; la mappa si svuota all'uscita dal gruppo.
class PartyQueueItems extends Notifier<Map<String, JellyfinItem?>> {
  /// Quanti id in una sola richiesta: gli id stanno nell'indirizzo, che il
  /// server limita in lunghezza, e una coda costruita da un altro client può
  /// avere più titoli di quelli che il gruppo accetta da qui.
  static const fetchChunk = 50;

  /// Dopo una richiesta non riuscita si riprova dopo questo tempo, anche se
  /// la coda non cambia.
  static const retryDelay = Duration(seconds: 5);

  /// Id chiesti e non ancora arrivati.
  final _requested = <String>{};

  /// Cambia all'uscita dal gruppo: una risposta arrivata dopo non vale più.
  int _generation = 0;

  Timer? _retryTimer;

  @override
  Map<String, JellyfinItem?> build() {
    _requested.clear();
    final generation = ++_generation;
    _cancelRetry();
    ref.onDispose(_cancelRetry);
    // Conta solo l'ingresso o l'uscita e la coda, non gli altri campi della
    // sessione (posizione, membri…).
    ref.listen(
        watchPartySessionProvider
            .select((s) => (inGroup: s.inGroup, queue: s.queue)),
        (_, party) => _sync(party.inGroup, party.queue));
    // La coda può esserci già (il player si apre a gruppo avviato): la si
    // legge dopo la costruzione, quando lo stato si può cambiare.
    scheduleMicrotask(() {
      if (ref.mounted && generation == _generation) _syncNow();
    });
    return const {};
  }

  void _syncNow() {
    final party = ref.read(watchPartySessionProvider);
    _sync(party.inGroup, party.queue);
  }

  void _sync(bool inGroup, PlayQueue? queue) {
    if (!inGroup) {
      _requested.clear();
      _generation++;
      _cancelRetry();
      if (state.isNotEmpty) state = const {};
      return;
    }
    if (queue == null) return;
    final missing = {
      for (final entry in queue.entries)
        if (!state.containsKey(entry.itemId) &&
            !_requested.contains(entry.itemId))
          entry.itemId,
    }.toList();
    if (missing.isEmpty) return;
    _requested.addAll(missing);
    unawaited(_fetch(missing, _generation));
  }

  /// Chiede [ids] a gruppi di [fetchChunk], uno dopo l'altro.
  Future<void> _fetch(List<String> ids, int generation) async {
    var start = 0;
    while (start < ids.length) {
      final chunk = ids.sublist(start, min(start + fetchChunk, ids.length));
      start += chunk.length;
      try {
        final items = await ref
            .read(libraryApiProvider)
            .itemsByIds(ref.read(currentUserIdProvider), chunk);
        if (!ref.mounted || generation != _generation) return;
        final byId = {for (final item in items) _normalizeId(item.id): item};
        _requested.removeAll(chunk);
        state = {
          ...state,
          for (final id in chunk) id: byId[_normalizeId(id)],
        };
      } on Object catch (error) {
        if (!ref.mounted || generation != _generation) return;
        _log.info('dettagli della coda non disponibili: ${error.runtimeType}');
        // Questo gruppo e quelli che non sono ancora partiti si richiedono
        // dopo [retryDelay], o prima se la coda cambia.
        _requested.removeAll(ids.sublist(start - chunk.length));
        _scheduleRetry(generation);
        return;
      }
    }
  }

  void _scheduleRetry(int generation) {
    if (_retryTimer?.isActive ?? false) return;
    _retryTimer = Timer(retryDelay, () {
      _retryTimer = null;
      if (ref.mounted && generation == _generation) _syncNow();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

final partyQueueItemsProvider =
    NotifierProvider<PartyQueueItems, Map<String, JellyfinItem?>>(
        PartyQueueItems.new);
