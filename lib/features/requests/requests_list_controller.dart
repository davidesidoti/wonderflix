import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/requests/requests_api.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../social/social_providers.dart';
import 'requests_providers.dart';

/// Un elenco della pagina Richieste: filtro e lingua dell'app.
typedef RequestsListKey = ({RequestsFilter filter, String language});

class RequestsListState {
  const RequestsListState({
    this.items = const [],
    this.hasMore = false,
    this.loading = false,
    this.error,
    this.busy = const {},
  });

  final List<MediaRequest> items;
  final bool hasMore;
  final bool loading;

  /// Errore dell'ultimo caricamento.
  final Object? error;

  /// Richieste con Approva o Rifiuta in viaggio: la riga è bloccata.
  final Set<int> busy;

  RequestsListState copyWith({
    List<MediaRequest>? items,
    bool? hasMore,
    bool? loading,
    Object? error,
    bool clearError = false,
    Set<int>? busy,
  }) =>
      RequestsListState(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
      );
}

/// Esito di Approva e Rifiuta, per l'avviso (spec I §9.4).
enum RequestActionOutcome { approved, declined, failed }

String requestActionText(AppLocalizations l, RequestActionOutcome outcome) =>
    switch (outcome) {
      RequestActionOutcome.approved => l.requestsStatusApproved,
      RequestActionOutcome.declined => l.requestsStatusDeclined,
      RequestActionOutcome.failed => l.requestsFailed,
    };

/// Un elenco della pagina Richieste (spec I §8.4): pagine di [pageSize],
/// ricarica a ogni avviso della cassetta, Approva e Rifiuta con la riga
/// bloccata finché la risposta non arriva.
class RequestsListController extends Notifier<RequestsListState> {
  RequestsListController(this.listKey);

  final RequestsListKey listKey;

  /// Richieste per pagina (spec I §8.4).
  static const pageSize = 20;

  /// Numera i caricamenti: vale solo l'ultimo.
  int _generation = 0;

  @override
  RequestsListState build() {
    // Un avviso nella cassetta (nuova richiesta, titolo arrivato) può
    // cambiare l'elenco; l'evento non dice il tipo della voce, quindi si
    // ricarica sempre (decisione 5 del piano 15b).
    final subscription = ref.watch(socialEventsProvider).listen((event) {
      if (event is InboxChangedEvent) unawaited(reload());
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    unawaited(Future.microtask(reload));
    return const RequestsListState(loading: true);
  }

  /// Dalla prima pagina. Le righe di prima restano finché non arrivano le nuove.
  Future<void> reload() => _load(reset: true);

  /// La pagina successiva. Dopo un errore si riprova solo dal pulsante.
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.error != null) return;
    await _load(reset: false);
  }

  /// La pagina successiva dopo un errore (il pulsante in fondo all'elenco).
  Future<void> loadMoreAfterError() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final previous = state.items;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref.read(requestsApiProvider).list(listKey.filter,
          skip: reset ? 0 : previous.length,
          take: pageSize,
          language: listKey.language);
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        items: reset ? page.items : [...previous, ...page.items],
        hasMore: page.hasMore,
        loading: false,
      );
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(loading: false, error: error);
    }
  }

  /// Approva con [choice]; `null` se era già in corso.
  Future<RequestActionOutcome?> approve(int requestId, ApproveChoice choice) =>
      _act(
          requestId,
          RequestActionOutcome.approved,
          (api) => api.approve(requestId, choice, language: listKey.language));

  /// Rifiuta; `null` se era già in corso.
  Future<RequestActionOutcome?> decline(int requestId) => _act(
      requestId,
      RequestActionOutcome.declined,
      (api) => api.decline(requestId, language: listKey.language));

  Future<RequestActionOutcome?> _act(int requestId, RequestActionOutcome done,
      Future<MediaRequest> Function(RequestsApi api) call) async {
    if (state.busy.contains(requestId)) return null;
    state = state.copyWith(busy: {...state.busy, requestId});
    RequestActionOutcome outcome;
    try {
      await call(ref.read(requestsApiProvider));
      outcome = done;
    } on Object {
      outcome = RequestActionOutcome.failed;
    }
    if (!ref.mounted) return outcome;
    final failed = outcome == RequestActionOutcome.failed;
    state = state.copyWith(
      items: failed
          ? state.items
          : [for (final request in state.items) if (request.id != requestId) request],
      busy: {...state.busy}..remove(requestId),
    );
    if (!failed) {
      // Il conteggio e l'elenco "Tutte" non sono più giusti.
      ref.invalidate(pendingRequestsCountProvider(listKey.language));
      ref.invalidate(requestsListControllerProvider(
          (filter: RequestsFilter.all, language: listKey.language)));
    }
    return outcome;
  }
}

final requestsListControllerProvider = NotifierProvider.autoDispose
    .family<RequestsListController, RequestsListState, RequestsListKey>(
        RequestsListController.new);

/// Quante richieste aspettano: la prima pagina di [pendingCountTake];
/// `more` se ce ne sono altre.
typedef PendingCount = ({int count, bool more});

/// Richieste contate per "Da approvare (n)" (decisione 6 del piano 15b).
const pendingCountTake = 50;

/// Il conteggio di "Da approvare" (spec I §8.4), per lingua. Si ricarica a
/// ogni avviso della cassetta e dopo Approva e Rifiuta.
final pendingRequestsCountProvider =
    FutureProvider.autoDispose.family<PendingCount, String>((ref, language) async {
  final subscription = ref.watch(socialEventsProvider).listen((event) {
    if (event is InboxChangedEvent) ref.invalidateSelf();
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
  final page = await ref.watch(requestsApiProvider).list(RequestsFilter.pending,
      skip: 0, take: pendingCountTake, language: language);
  return (count: page.items.length, more: page.hasMore);
});

/// "3", oppure "50+" se ce ne sono altre.
String pendingCountLabel(PendingCount count) =>
    count.more ? '${count.count}+' : '${count.count}';
