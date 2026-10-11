import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../auth/session_controller.dart';
import '../catalog/catalog_controller.dart';
import '../library/library_providers.dart';
import '../profiles/profile_preferences.dart';
import 'tonight_logic.dart';

/// Le preferenze del profilo con i filtri (spec M §8.4).
const tonightTypeKey = 'tonight.type';
const tonightDurationKey = 'tonight.duration';
const tonightGenreKey = 'tonight.genre';

/// I titoli già proposti in questa sessione per l'account collegato: non
/// tornano finché ce ne sono altri (decisione 6 del piano 19c).
class TonightSeen extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // Cambiando account si riparte da zero.
    ref.watch(sessionControllerProvider.select((session) =>
        session is SessionSignedIn ? session.user.id : null));
    return const {};
  }

  void add(String id) => state = {...state, id};

  void clear() => state = const {};
}

final tonightSeenProvider =
    NotifierProvider<TonightSeen, Set<String>>(TonightSeen.new);

/// I generi del menu: con "Entrambi" quelli dei film e delle serie insieme
/// (decisione 8 del piano 19c).
final tonightGenresProvider = FutureProvider.autoDispose
    .family<List<String>, TonightType>((ref, type) async {
  final lists = [
    for (final kind in type.kinds) ref.watch(catalogFiltersProvider(kind).future),
  ];
  return tonightGenreUnion(
      [for (final filters in await Future.wait(lists)) filters.genres]);
});

/// La finestra: i filtri e il titolo proposto.
@immutable
class TonightState {
  const TonightState({required this.filters, required this.pick});

  final TonightFilters filters;

  /// Il titolo proposto; `AsyncData(null)`: nessun titolo con questi filtri.
  final AsyncValue<JellyfinItem?> pick;
}

/// Pesca i titoli a gruppi di [tonightBatch] e li propone uno alla volta,
/// senza ripetere quelli già proposti (spec M §8.4).
class TonightController extends Notifier<TonightState> {
  /// I titoli dell'ultima pescata non ancora proposti.
  final _queue = <JellyfinItem>[];

  /// Cresce a ogni pescata: la risposta di una pescata superata si ignora.
  var _generation = 0;

  @override
  TonightState build() {
    final prefs = ref.read(profilePreferencesProvider);
    final genre = prefs.getString(tonightGenreKey);
    // La prima pescata parte appena la finestra c'è.
    unawaited(Future.microtask(another));
    return TonightState(
      filters: TonightFilters(
        type: TonightType.parse(prefs.getString(tonightTypeKey)),
        duration: TonightDuration.parse(prefs.getString(tonightDurationKey)),
        // In un profilo "nessun valore" è una stringa vuota (`clearString`).
        genre: genre == null || genre.isEmpty ? null : genre,
      ),
      pick: const AsyncLoading(),
    );
  }

  /// Cambia i filtri: si ricordano per il profilo e si riparte da capo.
  Future<void> setFilters(TonightFilters next) async {
    if (next == state.filters) return;
    _queue.clear();
    state = TonightState(filters: next, pick: state.pick);
    unawaited(another());
    final prefs = ref.read(profilePreferencesProvider);
    final genre = next.genre;
    await Future.wait([
      prefs.setString(tonightTypeKey, next.type.wire),
      prefs.setString(tonightDurationKey, next.duration.wire),
      genre == null
          ? prefs.clearString(tonightGenreKey)
          : prefs.setString(tonightGenreKey, genre),
    ]);
  }

  /// "Un altro", e la prima pescata: il prossimo titolo non ancora proposto.
  Future<void> another() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final filters = state.filters;
    state = TonightState(filters: filters, pick: const AsyncLoading());
    try {
      final item = await _next(filters, generation);
      if (!ref.mounted || generation != _generation) return;
      if (item != null) ref.read(tonightSeenProvider.notifier).add(item.id);
      state = TonightState(filters: filters, pick: AsyncData(item));
    } on Object catch (error, stack) {
      if (!ref.mounted || generation != _generation) return;
      state = TonightState(filters: filters, pick: AsyncError(error, stack));
    }
  }

  Future<JellyfinItem?> _next(TonightFilters filters, int generation) async {
    final seen = ref.read(tonightSeenProvider);
    while (_queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      if (!seen.contains(item.id)) return item;
    }
    final api = ref.read(libraryApiProvider);
    final userId = ref.read(currentUserIdProvider);
    final repeats = <String, JellyfinItem>{};
    for (var batch = 0; batch < tonightMaxBatches; batch++) {
      final page = await api.randomUnplayed(userId,
          kinds: filters.type.kinds, genre: filters.genre, limit: tonightBatch);
      if (!ref.mounted || generation != _generation) return null;
      final fresh = <String, JellyfinItem>{};
      for (final item in page.items) {
        if (!tonightEligible(item, filters)) continue;
        if (seen.contains(item.id)) {
          repeats[item.id] = item;
        } else {
          fresh[item.id] = item;
        }
      }
      if (fresh.isNotEmpty) {
        final items = fresh.values.toList();
        _queue.addAll(items.skip(1));
        return items.first;
      }
      // La pescata era già tutto: pescare ancora non serve.
      if (page.totalCount <= tonightBatch) break;
    }
    if (repeats.isEmpty) return null;
    // Già proposti tutti: si ricomincia con quelli (spec M §8.4, "finché ce
    // ne sono altri").
    ref.read(tonightSeenProvider.notifier).clear();
    final again = repeats.values.toList();
    _queue.addAll(again.skip(1));
    return again.first;
  }
}

final tonightControllerProvider =
    NotifierProvider.autoDispose<TonightController, TonightState>(
        TonightController.new);
