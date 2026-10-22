import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/activity_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/activity_controller.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

/// Come [FakeAdminApi], ma la risposta della prossima richiesta aspetta
/// [gate]: la richiesta è già registrata in `calls`.
class _GatedAdminApi extends FakeAdminApi {
  Completer<void>? gate;

  @override
  Future<ActivityPage> activity(
      {required int startIndex, bool? hasUserId}) async {
    final wait = gate;
    gate = null;
    final page =
        await super.activity(startIndex: startIndex, hasUserId: hasUserId);
    if (wait != null) await wait.future;
    return page;
  }
}

/// Come [FakeAdminApi], ma il totale che dà è [total] (se c'è): un server
/// che dice di avere più voci di quelle che poi restituisce.
class _TotalAdminApi extends FakeAdminApi {
  int? total;

  @override
  Future<ActivityPage> activity(
      {required int startIndex, bool? hasUserId}) async {
    final page =
        await super.activity(startIndex: startIndex, hasUserId: hasUserId);
    return ActivityPage(items: page.items, total: total ?? page.total);
  }
}

void main() {
  late FakeAdminApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAdminApi()..activityValue = testActivityEntries(120);
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(api, session: session),
      retry: (_, _) => null,
    );
    container.listen(activityControllerProvider, (_, _) {});
    return container;
  }

  ActivityState state(ProviderContainer container) =>
      container.read(activityControllerProvider);

  test('pagine da 50 dalla più recente, fino alla fine', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    expect(state(container).items, hasLength(50));
    expect(state(container).items.first.id, 120);
    expect(state(container).total, 120);
    expect(state(container).hasMore, isTrue);

    await controller.loadMore();
    await controller.loadMore();
    expect(state(container).items, hasLength(120));
    expect(state(container).hasMore, isFalse);
    expect(api.calls, ['activity:0:all', 'activity:50:all', 'activity:100:all']);

    await controller.loadMore();
    expect(api.count('activity:100:all'), 1, reason: 'non c\'è altro');
  });

  test('filtro: riparte dalla prima pagina, solo le voci giuste', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    await controller.setFilter(ActivityFilter.users);
    expect(state(container).filter, ActivityFilter.users);
    expect(state(container).items.every((e) => e.userId != null), isTrue);
    expect(state(container).total, 60);
    expect(api.calls.last, 'activity:0:true');

    await controller.setFilter(ActivityFilter.system);
    expect(state(container).items.every((e) => e.userId == null), isTrue);
    expect(api.calls.last, 'activity:0:false');
  });

  test('filtro cambiato mentre arriva una pagina: la risposta di prima si scarta',
      () async {
    final gated = _GatedAdminApi()..activityValue = testActivityEntries(120);
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(gated, session: session),
      retry: (_, _) => null,
    );
    container.listen(activityControllerProvider, (_, _) {});
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    // La seconda pagina di "Tutto" resta in viaggio...
    final gate = gated.gate = Completer<void>();
    final pending = controller.loadMore();
    await pumpEventQueue();
    // ...e intanto si passa a "Utenti".
    await controller.setFilter(ActivityFilter.users);
    gate.complete();
    await pending;

    expect(state(container).filter, ActivityFilter.users);
    expect(state(container).total, 60);
    expect(state(container).items, hasLength(50));
    expect(state(container).items.every((e) => e.userId != null), isTrue);
  });

  test('Aggiorna: di nuovo dalla prima pagina', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);
    await controller.loadMore();

    await controller.reload();
    expect(state(container).items, hasLength(50));
    expect(api.calls.last, 'activity:0:all');
  });

  test('Jellyfin torna da un riavvio: di nuovo dalla prima pagina', () async {
    final container = makeContainer();
    await pumpEventQueue();
    await container.read(activityControllerProvider.notifier).loadMore();
    expect(state(container).items, hasLength(100));
    final calls = api.calls.length;

    container.read(adminEpochProvider.notifier).bump();
    await pumpEventQueue();

    expect(api.calls.skip(calls), ['activity:0:all']);
    expect(state(container).items, hasLength(50));
  });

  test('voci nuove in cima tra una pagina e l\'altra: niente doppioni',
      () async {
    final container = makeContainer();
    await pumpEventQueue();
    // Arrivano tre voci nuove: la seconda pagina parte tre voci prima.
    api.activityValue = [
      for (var id = 123; id > 120; id--) ActivityEntry(id: id, name: 'Nuova $id'),
      ...api.activityValue,
    ];

    await container.read(activityControllerProvider.notifier).loadMore();

    final ids = state(container).items.map((e) => e.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, hasLength(97));
  });

  /// Voci nuove in cima al registro: id da [last] a [first] (decrescenti),
  /// prima di quelle di prima.
  void arrive(int last, int first) => api.activityValue = [
        for (var id = last; id >= first; id--)
          ActivityEntry(id: id, name: 'Nuova $id'),
        ...api.activityValue,
      ];

  test('tante voci nuove in cima tra una pagina e l\'altra: solo le più vecchie, '
      'in ordine', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);
    expect(state(container).items.last.id, 71);

    // Arrivano 60 voci, più di quelle mostrate: la pagina dopo (dall'indice
    // 50) ha solo voci più nuove di quelle in fondo all'elenco.
    arrive(180, 121);
    await controller.loadMore();

    var ids = state(container).items.map((e) => e.id).toList();
    expect(api.calls, ['activity:0:all', 'activity:50:all', 'activity:100:all'],
        reason: 'la pagina di voci già viste non ferma l\'elenco');
    expect(ids, [for (var id = 120; id >= 31; id--) id],
        reason: 'né voci più nuove in fondo, né buchi, né doppioni');
    expect(state(container).total, 180);
    expect(state(container).hasMore, isTrue);

    // Si continua fino alla fine; le 60 voci nuove si vedono con "Aggiorna".
    await controller.loadMore();
    ids = state(container).items.map((e) => e.id).toList();
    expect(ids, [for (var id = 120; id >= 1; id--) id]);
    expect(state(container).hasMore, isFalse);
    await controller.loadMore();
    expect(api.count('activity:150:all'), 1, reason: 'non c\'è altro');
  });

  test('centinaia di voci nuove: poche pagine per volta, poi si continua',
      () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    // 400 voci nuove: servono 8 pagine di voci più nuove prima di trovare
    // quelle più vecchie di quelle mostrate.
    arrive(520, 121);
    final before = api.calls.length;
    await controller.loadMore();

    expect(api.calls.skip(before), [
      for (var start = 50;
          start <= 50 + 50 * ActivityController.maxSkippedPages;
          start += 50)
        'activity:$start:all',
    ], reason: 'la prima pagina e al più ${ActivityController.maxSkippedPages} '
        'in più');
    expect(state(container).items, hasLength(50),
        reason: 'ancora niente di più vecchio');
    expect(state(container).loading, isFalse);
    expect(state(container).error, isNull);
    expect(state(container).hasMore, isTrue);

    // La volta dopo si riparte da dove si era arrivati.
    final afterFirst = api.calls.length;
    await controller.loadMore();
    final ids = state(container).items.map((e) => e.id).toList();
    expect(ids, [for (var id = 120; id >= 21; id--) id]);
    expect(api.calls.skip(afterFirst).first,
        'activity:${50 + 50 * (ActivityController.maxSkippedPages + 1)}:all',
        reason: 'nessuna pagina chiesta due volte');
  });

  test('il server dice di avere altre voci ma non ne dà: finisce, senza '
      'chiedere all\'infinito', () async {
    final server = _TotalAdminApi()
      ..activityValue = testActivityEntries(120)
      ..total = 200;
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(server, session: session),
      retry: (_, _) => null,
    );
    container.listen(activityControllerProvider, (_, _) {});
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    await controller.loadMore();
    await controller.loadMore();
    expect(state(container).items, hasLength(120));
    expect(state(container).hasMore, isTrue, reason: 'il totale dice 200');

    await controller.loadMore();
    expect(state(container).items, hasLength(120));
    expect(state(container).hasMore, isFalse,
        reason: 'una pagina vuota è la fine');
    expect(server.count('activity:120:all'), 1);

    await controller.loadMore();
    expect(server.count('activity:120:all'), 1);
  });

  test('errore: resta l\'elenco, Riprova ripete la pagina', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);

    api.activityError = const ServerUnreachableException();
    await controller.loadMore();
    expect(state(container).error, isA<ServerUnreachableException>());
    expect(state(container).items, hasLength(50));

    await controller.loadMore();
    expect(api.count('activity:50:all'), 1, reason: 'dopo un errore solo Riprova');

    api.activityError = null;
    await controller.retry();
    expect(state(container).error, isNull);
    expect(state(container).items, hasLength(100));
  });

  test('Aggiorna fallito con l\'elenco in mano: Riprova riparte dalla prima pagina',
      () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);
    await controller.loadMore();
    expect(state(container).items, hasLength(100));

    api.activityError = const ServerUnreachableException();
    await controller.reload();
    expect(state(container).error, isA<ServerUnreachableException>());
    expect(state(container).items, hasLength(100),
        reason: 'l\'elenco di prima resta');

    api.activityError = null;
    await controller.retry();
    expect(api.calls.last, 'activity:0:all',
        reason: 'si ripete la prima pagina, non si aggiunge in coda');
    expect(state(container).error, isNull);
    expect(state(container).items, hasLength(50));
  });

  test('403: rilegge l\'utente', () async {
    api.activityError = const ForbiddenException();
    makeContainer();
    await pumpEventQueue();

    expect(session.refreshUserCalls, 1);
  });
}
