import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/activity_models.dart';
import '../../core/jellyfin/api_exception.dart';
import '../auth/session_controller.dart';
import 'admin_providers.dart';

/// I filtri del Registro (spec J §9.5).
enum ActivityFilter {
  all(null),
  users(true),
  system(false);

  const ActivityFilter(this.hasUserId);

  /// Il parametro `hasUserId` di Jellyfin; `null` per tutte le voci.
  final bool? hasUserId;
}

class ActivityState {
  const ActivityState({
    this.filter = ActivityFilter.all,
    this.items = const [],
    this.total = 0,
    this.loading = false,
    this.error,
  });

  final ActivityFilter filter;

  /// Dalla più recente.
  final List<ActivityEntry> items;

  /// Le voci con questo filtro sul server.
  final int total;
  final bool loading;

  /// Errore dell'ultimo caricamento.
  final Object? error;

  bool get hasMore => items.length < total;

  ActivityState copyWith({
    List<ActivityEntry>? items,
    int? total,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      ActivityState(
        filter: filter,
        items: items ?? this.items,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Il Registro (spec J §9.5): pagine da 50 dalla voce più recente, filtri,
/// e nessuna rilettura automatica (le voci nuove in cima farebbero saltare
/// lo scorrimento): si ricarica all'apertura e con "Aggiorna".
class ActivityController extends Notifier<ActivityState> {
  /// Numera i caricamenti: vale solo l'ultimo.
  int _generation = 0;

  /// L'ultimo caricamento fallito ripartiva dalla prima pagina.
  bool _failedWasReset = false;

  @override
  ActivityState build() {
    // Dopo un riavvio di Jellyfin (come le altre schede) si riparte dalla
    // prima pagina: l'elenco di prima può non essere più quello del server.
    ref.listen<int>(adminEpochProvider, (_, _) => unawaited(reload()));
    unawaited(Future.microtask(reload));
    return const ActivityState(loading: true);
  }

  /// Dalla prima pagina, con il filtro di adesso.
  Future<void> reload() => _load(reset: true);

  /// Cambia filtro e riparte dalla prima pagina.
  Future<void> setFilter(ActivityFilter filter) {
    if (filter == state.filter) return Future.value();
    _generation++;
    state = ActivityState(filter: filter, loading: true);
    return _load(reset: true);
  }

  /// La pagina successiva. Dopo un errore si riprova solo da [retry].
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.error != null) return;
    await _load(reset: false);
  }

  /// "Riprova": ripete il caricamento che non è riuscito. Se era "Aggiorna"
  /// (o la prima pagina) riparte dalla prima pagina; se era la pagina dopo,
  /// ripete quella. Un "Aggiorna" fallito non deve aggiungere in coda alle
  /// voci già mostrate.
  Future<void> retry() => _load(reset: _failedWasReset || state.items.isEmpty);

  Future<void> _load({required bool reset}) async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final start = reset ? 0 : state.items.length;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref
          .read(adminApiProvider)
          .activity(startIndex: start, hasUserId: state.filter.hasUserId);
      if (!ref.mounted || generation != _generation) return;
      // Voci arrivate in cima tra una pagina e l'altra spostano gli indici:
      // la pagina dopo può ridare voci già mostrate.
      final shown = {
        for (final entry in reset ? const <ActivityEntry>[] : state.items)
          entry.id,
      };
      final fresh = [
        for (final entry in page.items)
          if (shown.add(entry.id)) entry,
      ];
      final items = reset ? fresh : [...state.items, ...fresh];
      state = state.copyWith(
        items: items,
        // Una pagina di soli doppioni: non c'è altro da chiedere.
        total: !reset && fresh.isEmpty ? items.length : page.total,
        loading: false,
      );
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      if (error is ForbiddenException) {
        unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
      }
      _failedWasReset = reset;
      state = state.copyWith(loading: false, error: error);
    }
  }
}

final activityControllerProvider =
    NotifierProvider.autoDispose<ActivityController, ActivityState>(
        ActivityController.new);
