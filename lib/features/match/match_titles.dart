import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../library/library_providers.dart';
import 'match_room_controller.dart';

final _log = Logger('match');

/// I titoli della pila della sala (spec P §7.3), per id. `null` = il server
/// non lo restituisce (cancellato o non visibile): la votazione lo salta con
/// un "no". Si chiedono solo gli id nuovi; cambiando sala si riparte da zero.
class MatchTitles extends Notifier<Map<String, JellyfinItem?>> {
  String? _roomId;

  /// Id già chiesti e non ancora tornati: un altro stato non li richiede.
  final _asked = <String>{};

  @override
  Map<String, JellyfinItem?> build() {
    ref.listen(matchRoomProvider, (_, view) => unawaited(_sync(view)));
    // Lo stato non si può cambiare durante la build: il primo carico parte dopo.
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(_sync(ref.read(matchRoomProvider)));
    });
    return const {};
  }

  Future<void> _sync(MatchRoomView? view) async {
    final roomId = view?.roomId;
    if (roomId != _roomId) {
      _roomId = roomId;
      _asked.clear();
      state = const {};
    }
    final ids = [
      for (final id in view?.state?.stack ?? const <String>[])
        if (!state.containsKey(id) && _asked.add(id)) id,
    ];
    if (ids.isEmpty) return;
    final ref = this.ref;
    try {
      final found = await ref
          .read(libraryApiProvider)
          .itemsByIds(ref.read(currentUserIdProvider), ids);
      if (!ref.mounted || _roomId != roomId) return;
      final byId = {for (final item in found) item.id: item};
      state = {
        ...state,
        for (final id in ids) id: byId[id],
      };
    } on Object catch (error) {
      // Gli id restano da chiedere al prossimo stato; niente titoli nei log.
      _log.info('titoli del match non caricati: ${error.runtimeType}');
      if (_roomId == roomId) _asked.removeAll(ids);
    }
  }
}

final matchTitlesProvider =
    NotifierProvider<MatchTitles, Map<String, JellyfinItem?>>(MatchTitles.new);
