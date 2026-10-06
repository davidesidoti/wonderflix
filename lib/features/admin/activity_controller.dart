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
    this.cursor = 0,
    this.loading = false,
    this.error,
  });

  final ActivityFilter filter;

  /// Dalla più recente.
  final List<ActivityEntry> items;

  /// Le voci con questo filtro sul server.
  final int total;

  /// Il `startIndex` della pagina dopo: quante voci il server ha già dato.
  /// Non è `items.length`: le voci arrivate in cima dopo la prima pagina
  /// spostano gli indici, e delle pagine dopo si tengono solo le voci più
  /// vecchie di quelle mostrate.
  final int cursor;
  final bool loading;

  /// Errore dell'ultimo caricamento.
  final Object? error;

  /// Ci sono altre voci da chiedere al server.
  bool get hasMore => cursor < total;

  ActivityState copyWith({
    List<ActivityEntry>? items,
    int? total,
    int? cursor,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      ActivityState(
        filter: filter,
        items: items ?? this.items,
        total: total ?? this.total,
        cursor: cursor ?? this.cursor,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Il Registro (spec J §9.5): pagine da 50 dalla voce più recente, filtri,
/// e nessuna rilettura automatica (le voci nuove in cima farebbero saltare
/// lo scorrimento): si ricarica all'apertura e con "Aggiorna".
class ActivityController extends Notifier<ActivityState> {
  /// Pagine in più che una richiesta di [loadMore] chiede di fila, se quella
  /// prima ha solo voci più nuove di quelle mostrate (arrivate in cima mentre
  /// si guardava): fino a 250 voci scartate, poi si ferma finché la vista non
  /// chiede ancora. Così una raffica di voci nuove non lascia l'elenco fermo
  /// né fa chiedere centinaia di pagine in un colpo.
  static const maxSkippedPages = 5;

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
    // `_load` numera il caricamento: quello in corso con il filtro di prima
    // vale meno e si scarta.
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
    state = state.copyWith(loading: true, clearError: true);
    try {
      var cursor = reset ? 0 : state.cursor;
      var skipped = 0;
      while (true) {
        final page = await ref
            .read(adminApiProvider)
            .activity(startIndex: cursor, hasUserId: state.filter.hasUserId);
        if (!ref.mounted || generation != _generation) return;
        // Una pagina vuota con altre voci "in arrivo" (il registro si è
        // accorciato mentre si guardava) è la fine: altrimenti si
        // richiederebbe all'infinito.
        cursor = page.items.isEmpty ? page.total : cursor + page.items.length;

        if (reset) {
          state = state.copyWith(
            items: page.items,
            total: page.total,
            cursor: cursor,
            loading: false,
          );
          return;
        }

        // L'`Id` cresce con il tempo: le voci della pagina dopo, in ordine,
        // sono solo quelle più vecchie dell'ultima mostrata. Le altre sono
        // voci arrivate in cima nel frattempo (che spostano gli indici e
        // ridanno voci già viste, o danno voci più nuove): si vedono con
        // "Aggiorna".
        final shown = state.items;
        final lastId = shown.isEmpty ? null : shown.last.id;
        final older = [
          for (final entry in page.items)
            if (lastId == null || entry.id < lastId) entry,
        ];
        final done = older.isNotEmpty ||
            cursor >= page.total ||
            skipped >= maxSkippedPages;
        state = state.copyWith(
          items: [...shown, ...older],
          total: page.total,
          cursor: cursor,
          // Finché si cerca ancora, la pagina resta in caricamento. Il cursore
          // però avanza subito: dopo un errore, "Riprova" riparte da lì.
          loading: !done,
        );
        if (done) return;
        skipped++;
      }
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
