import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/requests/requests_list_controller.dart';

import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;
  late StreamController<SocialEvent> events;
  const mine = (filter: RequestsFilter.mine, language: 'it');
  const pending = (filter: RequestsFilter.pending, language: 'it');

  setUp(() {
    api = FakeRequestsApi();
    events = StreamController<SocialEvent>.broadcast();
  });

  tearDown(() => events.close());

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: requestsTestOverrides(api, events: events.stream),
      retry: (_, _) => null,
    );
    container.listen(requestsListControllerProvider(mine), (_, _) {});
    container.listen(requestsListControllerProvider(pending), (_, _) {});
    return container;
  }

  List<MediaRequest> requests(int count) =>
      [for (var i = 1; i <= count; i++) testMediaRequest(id: i, title: 'Titolo $i')];

  test('carica a pagine di 20, poi le altre', () async {
    api.lists[RequestsFilter.mine] = requests(25);
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(requestsListControllerProvider(mine).notifier);

    expect(container.read(requestsListControllerProvider(mine)).items, hasLength(20));
    expect(container.read(requestsListControllerProvider(mine)).hasMore, isTrue);
    expect(api.calls, contains('list:mine:0:20'));

    await controller.loadMore();
    expect(container.read(requestsListControllerProvider(mine)).items, hasLength(25));
    expect(container.read(requestsListControllerProvider(mine)).hasMore, isFalse);
    expect(api.calls, contains('list:mine:20:20'));

    await controller.loadMore();
    expect(api.calls.where((c) => c.startsWith('list:mine')), hasLength(2));
  });

  test('ricarica a ogni avviso della cassetta', () async {
    final container = makeContainer();
    await pumpEventQueue();

    events.add(const InboxChangedEvent());
    await pumpEventQueue();

    expect(api.calls.where((c) => c == 'list:mine:0:20'), hasLength(2));
    expect(container.read(requestsListControllerProvider(mine)).loading, isFalse);
  });

  test('errore, poi Riprova', () async {
    api.failure = RequestsFailure.network;
    final container = makeContainer();
    await pumpEventQueue();
    expect(container.read(requestsListControllerProvider(mine)).error,
        isA<RequestsException>());

    api
      ..failure = null
      ..lists[RequestsFilter.mine] = requests(1);
    await container.read(requestsListControllerProvider(mine).notifier).reload();

    final state = container.read(requestsListControllerProvider(mine));
    expect(state.error, isNull);
    expect(state.items, hasLength(1));
  });

  test('Approva: la riga è bloccata durante l\'invio, poi esce', () async {
    api.lists[RequestsFilter.pending] = requests(2);
    final gate = api.actionGate = Completer<void>();
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestsListControllerProvider(pending).notifier);
    const choice =
        ApproveChoice(serverId: 1, profileId: 7, rootFolder: '/media/anime');

    final first = controller.approve(1, choice);
    expect(container.read(requestsListControllerProvider(pending)).busy, {1});
    expect(await controller.approve(1, choice), isNull);
    gate.complete();

    expect(await first, RequestActionOutcome.approved);
    final state = container.read(requestsListControllerProvider(pending));
    expect(state.items.map((r) => r.id), [2]);
    expect(state.busy, isEmpty);
    expect(api.approved.single.id, 1);
    expect(api.approved.single.choice.profileId, 7);
  });

  test('Rifiuta toglie la riga e fa ricontare', () async {
    api.lists[RequestsFilter.pending] = requests(2);
    final container = makeContainer();
    container.listen(pendingRequestsCountProvider('it'), (_, _) {});
    await pumpEventQueue();
    expect(container.read(pendingRequestsCountProvider('it')).value,
        (count: 2, more: false));

    expect(
        await container
            .read(requestsListControllerProvider(pending).notifier)
            .decline(2),
        RequestActionOutcome.declined);
    await pumpEventQueue();

    expect(api.declined, [2]);
    expect(
        container.read(requestsListControllerProvider(pending)).items.map((r) => r.id),
        [1]);
    expect(api.calls.where((c) => c == 'list:pending:0:50'), hasLength(2));
  });

  test('un errore lascia la riga', () async {
    api
      ..lists[RequestsFilter.pending] = requests(2)
      ..actionFailure = RequestsFailure.seerrUnavailable;
    final container = makeContainer();
    await pumpEventQueue();

    expect(
        await container
            .read(requestsListControllerProvider(pending).notifier)
            .decline(1),
        RequestActionOutcome.failed);

    final state = container.read(requestsListControllerProvider(pending));
    expect(state.items, hasLength(2));
    expect(state.busy, isEmpty);
  });

  test('conteggio: oltre 50 è "50+", e si ricarica con la cassetta', () async {
    api.lists[RequestsFilter.pending] = requests(55);
    final container = makeContainer();
    container.listen(pendingRequestsCountProvider('it'), (_, _) {});
    await pumpEventQueue();

    final count = container.read(pendingRequestsCountProvider('it')).value!;
    expect(count, (count: 50, more: true));
    expect(pendingCountLabel(count), '50+');
    expect(pendingCountLabel((count: 3, more: false)), '3');

    events.add(const InboxChangedEvent());
    await pumpEventQueue();
    expect(api.calls.where((c) => c == 'list:pending:0:50'), hasLength(2));
  });

  test('con meno di una pagina e altre sul server, ne chiede altre', () async {
    api.lists[RequestsFilter.pending] = requests(25);
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestsListControllerProvider(pending).notifier);
    expect(container.read(requestsListControllerProvider(pending)).items,
        hasLength(20));

    // Il server toglie la richiesta approvata dall'elenco: le altre scalano.
    api.lists[RequestsFilter.pending] = requests(25).skip(1).toList();
    expect(
        await controller.approve(1, ApproveChoice.defaults),
        RequestActionOutcome.approved);
    await pumpEventQueue();

    expect(api.calls, contains('list:pending:19:20'));
    final state = container.read(requestsListControllerProvider(pending));
    expect(state.items.map((r) => r.id), [for (var i = 2; i <= 25; i++) i]);
    expect(state.hasMore, isFalse);
  });

  test('tolte tutte le righe, se il server ne ha altre le chiede', () async {
    api.lists[RequestsFilter.pending] = requests(25);
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestsListControllerProvider(pending).notifier);

    for (var id = 1; id <= 20; id++) {
      api.lists[RequestsFilter.pending] = requests(25).skip(id).toList();
      await controller.decline(id);
      await pumpEventQueue();
    }

    final state = container.read(requestsListControllerProvider(pending));
    expect(state.items.map((r) => r.id), [for (var i = 21; i <= 25; i++) i]);
    expect(state.hasMore, isFalse);
  });

  test('una pagina in viaggio non rimette la riga approvata nel frattempo',
      () async {
    api.lists[RequestsFilter.pending] = requests(25);
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestsListControllerProvider(pending).notifier);

    final gate = api.listGate = Completer<void>();
    final more = controller.loadMore();
    expect(await controller.approve(1, ApproveChoice.defaults),
        RequestActionOutcome.approved);
    gate.complete();
    await more;

    final ids = container
        .read(requestsListControllerProvider(pending))
        .items
        .map((r) => r.id);
    expect(ids, [for (var i = 2; i <= 25; i++) i]);
  });

  test('un ricaricamento partito prima non rimette la riga rifiutata',
      () async {
    api.lists[RequestsFilter.pending] = requests(2);
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestsListControllerProvider(pending).notifier);

    // Il ricaricamento vede ancora le due richieste (risposta di prima).
    final gate = api.listGate = Completer<void>();
    final reload = controller.reload();
    expect(await controller.decline(1), RequestActionOutcome.declined);
    gate.complete();
    await reload;

    final state = container.read(requestsListControllerProvider(pending));
    expect(state.items.map((r) => r.id), [2]);
    expect(state.loading, isFalse);
  });

  test('una riga già mostrata non si ripete nella pagina dopo', () async {
    api.lists[RequestsFilter.mine] = requests(25);
    final container = makeContainer();
    await pumpEventQueue();

    // Una nuova richiesta in cima sposta gli offset di una riga.
    api.lists[RequestsFilter.mine] = [
      testMediaRequest(id: 99, title: 'Nuova'),
      ...requests(25),
    ];
    await container.read(requestsListControllerProvider(mine).notifier).loadMore();

    final ids = container
        .read(requestsListControllerProvider(mine))
        .items
        .map((r) => r.id)
        .toList();
    expect(ids, [for (var i = 1; i <= 25; i++) i]);
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('cambiando scheda durante Rifiuta, il conteggio si aggiorna lo stesso',
      () async {
    api.lists[RequestsFilter.pending] = requests(2);
    final container = ProviderContainer.test(
      overrides: requestsTestOverrides(api, events: events.stream),
      retry: (_, _) => null,
    );
    final list = container.listen(requestsListControllerProvider(pending), (_, _) {});
    container.listen(pendingRequestsCountProvider('it'), (_, _) {});
    await pumpEventQueue();
    final controller =
        container.read(requestsListControllerProvider(pending).notifier);

    final gate = api.actionGate = Completer<void>();
    final action = controller.decline(1);
    // L'utente cambia scheda: la pagina non ascolta più l'elenco.
    list.close();
    await pumpEventQueue();
    gate.complete();
    expect(await action, RequestActionOutcome.declined);
    await pumpEventQueue();

    expect(api.calls.where((c) => c == 'list:pending:0:50'), hasLength(2));
  });

  test('Riprova dopo un ricaricamento fallito ricarica da capo', () async {
    api.lists[RequestsFilter.mine] = requests(25);
    final container = makeContainer();
    await pumpEventQueue();
    expect(container.read(requestsListControllerProvider(mine)).items, hasLength(20));

    api.failure = RequestsFailure.network;
    events.add(const InboxChangedEvent());
    await pumpEventQueue();
    expect(container.read(requestsListControllerProvider(mine)).error,
        isA<RequestsException>());

    api.failure = null;
    api.calls.clear();
    await container.read(requestsListControllerProvider(mine).notifier).retry();

    expect(api.calls, ['list:mine:0:20']);
    final state = container.read(requestsListControllerProvider(mine));
    expect(state.error, isNull);
    expect(state.items, hasLength(20));
  });

  test('Riprova dopo una pagina fallita chiede la pagina dopo', () async {
    api.lists[RequestsFilter.mine] = requests(25);
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(requestsListControllerProvider(mine).notifier);

    api.failure = RequestsFailure.network;
    await controller.loadMore();
    expect(container.read(requestsListControllerProvider(mine)).error, isNotNull);

    api.failure = null;
    api.calls.clear();
    await controller.retry();

    expect(api.calls, ['list:mine:20:20']);
    expect(container.read(requestsListControllerProvider(mine)).items, hasLength(25));
  });
}
