import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/json_fields.dart';
import '../home/home_providers.dart';
import 'library_providers.dart';

final _log = Logger('library');

/// Quando ogni titolo è entrato in "La mia lista": Jellyfin non tiene la data
/// dei preferiti, la tiene l'app nelle `DisplayPreferences` dell'utente
/// (`myListAdded`). Chiavi `jellyfinIdKey`; si rilegge al cambio di utente.
/// Stessa struttura di `NextUpHidden`: scritture in fila, una rilettura dopo
/// una lettura fallita.
class MyListAdded extends AsyncNotifier<Map<String, DateTime>> {
  /// La scrittura in corso: una alla volta, perché ognuna rilegge e riscrive
  /// l'oggetto intero.
  Future<void> _writes = Future.value();

  /// La lettura all'apertura non è riuscita: prima di scrivere si rilegge,
  /// se no si cancellerebbero le date già salvate.
  bool _stale = false;
  Future<Map<String, DateTime>>? _reread;

  @override
  Future<Map<String, DateTime>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    _stale = false;
    _reread = null;
    try {
      return await ref
          .watch(displayPreferencesApiProvider)
          .readMyListAdded(userId);
    } on Object catch (error) {
      _log.info('Date di La mia lista non lette: ${error.runtimeType}');
      _stale = true;
      return const {};
    }
  }

  /// Mette ([DateTime]) o toglie (`null`) le date di [changes], con una sola
  /// scrittura; `false` se non si è salvato (lo stato torna com'era).
  Future<bool> change(Map<String, DateTime?> changes) async {
    final api = ref.read(displayPreferencesApiProvider);
    final userId = ref.read(currentUserIdProvider);
    await future;
    if (_stale) {
      // Una sola rilettura anche con più modifiche insieme: la seconda trova
      // nello stato quella della prima.
      try {
        final server = await (_reread ??= api.readMyListAdded(userId));
        if (_stale) {
          state = AsyncData(server);
          _stale = false;
        }
      } on Object catch (error) {
        _reread = null;
        _log.info('Date di La mia lista non lette: ${error.runtimeType}');
        return false;
      }
    }
    // Lo stato, non `future`: una modifica appena prima è già lì.
    final current = state.value ?? const <String, DateTime>{};
    final keys = {
      for (final MapEntry(:key, :value) in changes.entries)
        jellyfinIdKey(key): value,
    };
    final before = {
      for (final key in keys.keys)
        key: ?current[key],
    };
    state = AsyncData(_with(current, keys));
    // La mappa si prende quando tocca a questa scrittura: la più recente. Se
    // fallisce si torna indietro prima della scrittura dopo, che se no la
    // manderebbe lo stesso.
    final done = _writes
        .then((_) => api.writeMyListAdded(userId, state.value ?? const {}))
        .then<bool>((_) => true, onError: (Object error) {
      _log.info('Date di La mia lista non salvate: ${error.runtimeType}');
      if (ref.mounted) {
        state = AsyncData(
          _with(state.value ?? const {}, {
            for (final key in keys.keys) key: before[key],
          }),
        );
      }
      return false;
    });
    _writes = done;
    return done;
  }

  /// Tiene solo le date di [ids] (chiavi `jellyfinIdKey`): i titoli usciti
  /// dalla lista. Non scrive: la pulizia va sul server con la scrittura dopo.
  void retainOnly(Set<String> ids) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData({
      for (final MapEntry(:key, :value) in current.entries)
        if (ids.contains(key)) key: value,
    });
  }

  static Map<String, DateTime> _with(
    Map<String, DateTime> map,
    Map<String, DateTime?> changes,
  ) {
    final result = {...map};
    for (final MapEntry(:key, :value) in changes.entries) {
      if (value == null) {
        result.remove(key);
      } else {
        result[key] = value;
      }
    }
    return result;
  }
}

final myListAddedProvider =
    AsyncNotifierProvider<MyListAdded, Map<String, DateTime>>(MyListAdded.new);
