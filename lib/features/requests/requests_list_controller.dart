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
/// aggiornamento delle righe mostrate a ogni avviso della cassetta, Approva e
/// Rifiuta con la riga bloccata finché la risposta non arriva.
class RequestsListController extends Notifier<RequestsListState> {
  RequestsListController(this.listKey);

  final RequestsListKey listKey;

  /// Richieste per pagina (spec I §8.4).
  static const pageSize = 20;

  /// Quante righe si rileggono in una chiamata sola per aggiornare l'elenco:
  /// il massimo che il plugin dà (`take`). Oltre, le righe restano come sono.
  static const maxRefreshTake = 50;

  /// Numera i caricamenti: vale solo l'ultimo.
  int _generation = 0;

  /// Le richieste su cui Approva o Rifiuta è riuscito: una lettura partita
  /// prima non le rimette nell'elenco.
  final _removed = <int>{};

  /// Se l'ultimo caricamento fallito ripartiva dalla prima pagina: [retry]
  /// ne ripete lo stesso tipo (un ricaricamento non deve diventare una
  /// pagina in più).
  bool _failedWasReset = true;

  @override
  RequestsListState build() {
    // Un avviso nella cassetta (nuova richiesta, titolo arrivato) può
    // cambiare l'elenco; l'evento non dice il tipo della voce, quindi si
    // aggiorna sempre (decisione 5 del piano 15b). Anche aprire il pannello
    // delle notifiche ne manda uno: l'elenco non deve accorciarsi.
    final subscription = ref.watch(socialEventsProvider).listen((event) {
      if (event is InboxChangedEvent) unawaited(refresh());
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    unawaited(Future.microtask(reload));
    return const RequestsListState(loading: true);
  }

  /// Dalla prima pagina, e solo quella: l'elenco riparte da venti righe. Le
  /// righe di prima restano finché non arrivano le nuove.
  Future<void> reload() => _load(reset: true);

  /// Rilegge le righe mostrate, fino a [maxRefreshTake], senza accorciare
  /// l'elenco (un avviso della cassetta, Approva e Rifiuta in un'altra
  /// scheda). Senza righe è un ricaricamento come gli altri.
  Future<void> refresh() {
    if (state.items.isEmpty) return reload();
    return _refresh();
  }

  /// La pagina successiva. Dopo un errore si riprova solo dal pulsante.
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.error != null) return;
    await _load(reset: false);
  }

  /// Ripete il caricamento fallito (il pulsante in fondo all'elenco): da
  /// capo se era un ricaricamento, la pagina dopo se era una pagina.
  Future<void> retry() => _load(reset: _failedWasReset);

  Future<void> _load({required bool reset}) async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    // Le righe mostrate sono quelle che il server ha dato e non ha ancora
    // tolto (Approva e Rifiuta le tolgono da tutte e due le parti): la pagina
    // dopo parte da lì. Una riga con Approva o Rifiuta in viaggio non si
    // conta: se il server l'ha già tolta, l'offset è giusto; se no, la pagina
    // si sovrappone di una riga e il doppione sparisce.
    final skip = reset
        ? 0
        : state.items.length -
            state.items.where((r) => state.busy.contains(r.id)).length;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref.read(requestsApiProvider).list(listKey.filter,
          skip: skip, take: pageSize, language: listKey.language);
      if (!ref.mounted || generation != _generation) return;
      // Una lettura partita prima di Approva o Rifiuta non disfa l'azione:
      // le righe tolte non tornano, e la pagina si aggiunge alle righe di
      // adesso. Se nuove richieste hanno spostato gli offset, il server può
      // ridare una riga già mostrata: niente doppioni.
      final shown = {
        for (final request in reset ? const <MediaRequest>[] : state.items)
          request.id,
      };
      final fresh = [
        for (final request in page.items)
          if (!_removed.contains(request.id) && shown.add(request.id)) request,
      ];
      state = state.copyWith(
        items: reset ? fresh : [...state.items, ...fresh],
        hasMore: page.hasMore,
        loading: false,
      );
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      _failedWasReset = reset;
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> _refresh() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    // Le prime `take` righe si sostituiscono con quelle nuove, le altre
    // (le pagine arrivate dopo) restano. Se richieste nuove in cima spingono
    // una riga oltre `take`, quella non rientra: la ridà un ricaricamento.
    final take = state.items.length.clamp(pageSize, maxRefreshTake);
    final head = {for (final request in state.items.take(take)) request.id};
    // Non si azzera `error`: se una pagina era fallita, il pulsante resta
    // finché il caricamento non riesce davvero.
    state = state.copyWith(loading: true);
    try {
      final page = await ref.read(requestsApiProvider).list(listKey.filter,
          skip: 0, take: take, language: listKey.language);
      if (!ref.mounted || generation != _generation) return;
      // Come in `_load`: una lettura partita prima di Approva o Rifiuta non
      // rimette la riga tolta, e niente doppioni.
      final fresh = <MediaRequest>[];
      final freshIds = <int>{};
      for (final request in page.items) {
        if (!_removed.contains(request.id) && freshIds.add(request.id)) {
          fresh.add(request);
        }
      }
      final kept = [
        for (final request in state.items)
          if (!head.contains(request.id) &&
              !freshIds.contains(request.id) &&
              !_removed.contains(request.id))
            request,
      ];
      state = state.copyWith(
        items: [...fresh, ...kept],
        // Con righe oltre le prime `take` il server ne ha di sicuro altre
        // (quelle che si erano già caricate): vale quello di prima.
        hasMore: kept.isEmpty ? page.hasMore : state.hasMore,
        loading: false,
        clearError: true,
      );
    } on Object {
      // Un aggiornamento in secondo piano che non riesce non cambia l'elenco
      // e non porta un errore: le prime righe si aggiornano al prossimo avviso.
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(loading: false);
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
    // Il controller resta vivo finché la risposta non arriva: se nel
    // frattempo si cambia scheda, il conteggio e l'elenco "Tutte" si
    // aggiornano lo stesso.
    final link = ref.keepAlive();
    try {
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
      // Una lettura partita prima non rimette la riga tolta (non si
      // aggiorna `_generation`: il suo `loading` non finirebbe più).
      if (!failed) _removed.add(requestId);
      state = state.copyWith(
        items: failed
            ? state.items
            : [for (final request in state.items) if (request.id != requestId) request],
        busy: {...state.busy}..remove(requestId),
      );
      if (!failed) {
        // Il conteggio non è più giusto. L'elenco "Tutte", se c'è, si
        // aggiorna dov'è: ricrearlo lo svuoterebbe e perderebbe lo scroll.
        ref.invalidate(pendingRequestsCountProvider(listKey.language));
        final all = requestsListControllerProvider(
            (filter: RequestsFilter.all, language: listKey.language));
        if (ref.exists(all)) unawaited(ref.read(all.notifier).refresh());
        // Con meno di una pagina e altre sul server, l'elenco non resta
        // corto (e, se si è svuotato, non resta vuoto).
        if (state.hasMore && state.items.length < pageSize) {
          unawaited(loadMore());
        }
      }
      return outcome;
    } finally {
      link.close();
    }
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
