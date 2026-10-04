import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../library/library_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Dettagli dei titoli nella coda del gruppo (spec H §8.5), per `ItemId`:
/// assente = in arrivo, `null` = non disponibile (cancellato, o non più
/// visibile). Gli id nuovi si chiedono tutti insieme con `itemsByIds` (sono
/// al massimo 100); la mappa si svuota all'uscita dal gruppo.
class PartyQueueItems extends Notifier<Map<String, JellyfinItem?>> {
  /// Id chiesti e non ancora arrivati.
  final _requested = <String>{};

  /// Cambia all'uscita dal gruppo: una risposta arrivata dopo non vale più.
  int _generation = 0;

  @override
  Map<String, JellyfinItem?> build() {
    _requested.clear();
    final generation = ++_generation;
    ref.listen(watchPartySessionProvider, (_, party) => _sync(party));
    // La coda può esserci già (il player si apre a gruppo avviato): la si
    // legge dopo la costruzione, quando lo stato si può cambiare.
    scheduleMicrotask(() {
      if (ref.mounted && generation == _generation) {
        _sync(ref.read(watchPartySessionProvider));
      }
    });
    return const {};
  }

  void _sync(WatchPartyState party) {
    if (!party.inGroup) {
      _requested.clear();
      _generation++;
      if (state.isNotEmpty) state = const {};
      return;
    }
    final queue = party.queue;
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

  Future<void> _fetch(List<String> ids, int generation) async {
    try {
      final items = await ref
          .read(libraryApiProvider)
          .itemsByIds(ref.read(currentUserIdProvider), ids);
      if (!ref.mounted || generation != _generation) return;
      final byId = {for (final item in items) _normalizeId(item.id): item};
      _requested.removeAll(ids);
      state = {
        ...state,
        for (final id in ids) id: byId[_normalizeId(id)],
      };
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      _log.info('dettagli della coda non disponibili: ${error.runtimeType}');
      // Al prossimo aggiornamento della coda si riprova.
      _requested.removeAll(ids);
    }
  }
}

final partyQueueItemsProvider =
    NotifierProvider<PartyQueueItems, Map<String, JellyfinItem?>>(
        PartyQueueItems.new);
