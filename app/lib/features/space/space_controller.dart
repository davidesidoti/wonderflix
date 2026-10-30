import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/space/space_api.dart';
import '../../core/space/space_models.dart';
import '../admin/admin_providers.dart';
import '../social/social_providers.dart';
import 'space_providers.dart';

final _log = Logger('space');

/// La panoramica dello spazio (spec U §8), solo per un admin con la funzione
/// `space`; per gli altri è vuota.
class SpaceController extends AsyncNotifier<SpaceOverview> {
  /// Cresce a ogni lettura: vale solo la risposta dell'ultima.
  int _loads = 0;

  @override
  Future<SpaceOverview> build() async {
    final admin = ref.watch(isAdminProvider);
    final enabled = ref.watch(
      socialAvailabilityProvider.select((f) => f.space),
    );
    final api = ref.watch(spaceApiProvider);
    if (!admin || !enabled) return SpaceOverview.empty;
    _loads++;
    return api.overview();
  }

  /// Rilegge. Un errore lascia la panoramica di prima; senza una finisce nello
  /// stato.
  Future<void> reload() async {
    if (!ref.mounted || !ref.read(isAdminProvider)) return;
    final api = ref.read(spaceApiProvider);
    final load = ++_loads;
    try {
      final overview = await api.overview();
      if (!ref.mounted || load != _loads) return;
      state = AsyncData(overview);
    } on Object catch (error, stack) {
      _log.info(
        'spazio non caricato: '
        '${error is SpaceException ? error.failure.name : error.runtimeType}',
      );
      if (!ref.mounted || load != _loads || state.hasValue) return;
      state = AsyncError(error, stack);
    }
  }

  /// Chiede un nuovo calcolo; la scheda rilegge a 5 s finché `scanning`.
  Future<SpaceFailure?> recalculate() =>
      _then(() => ref.read(spaceApiProvider).recalculate());

  Future<SpaceFailure?> keep(String key, String title) =>
      _then(() => ref.read(spaceApiProvider).keep(key, title));

  /// Tiene ciascuno in ordine e rilegge una volta sola; dà gli errori.
  Future<List<SpaceFailure>> keepAll(List<(String, String)> items) async {
    final failures = <SpaceFailure>[];
    for (final (key, title) in items) {
      try {
        await ref.read(spaceApiProvider).keep(key, title);
      } on SpaceException catch (error) {
        failures.add(error.failure);
      }
    }
    await reload();
    return failures;
  }

  Future<SpaceFailure?> unkeep(String key) =>
      _then(() => ref.read(spaceApiProvider).unkeep(key));

  Future<SpaceFailure?> dropPending(String hash) =>
      _then(() => ref.read(spaceApiProvider).dropPending(hash));

  /// L'azione, poi la lettura; dà l'errore dell'azione, se c'è.
  Future<SpaceFailure?> _then(Future<void> Function() action) async {
    try {
      await action();
    } on SpaceException catch (error) {
      return error.failure;
    }
    await reload();
    return null;
  }
}

final spaceControllerProvider =
    AsyncNotifierProvider.autoDispose<SpaceController, SpaceOverview>(
      SpaceController.new,
    );
