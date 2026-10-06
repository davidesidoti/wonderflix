import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/activity_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/activity_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

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

  test('Aggiorna: di nuovo dalla prima pagina', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller = container.read(activityControllerProvider.notifier);
    await controller.loadMore();

    await controller.reload();
    expect(state(container).items, hasLength(50));
    expect(api.calls.last, 'activity:0:all');
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

  test('403: rilegge l\'utente', () async {
    api.activityError = const ForbiddenException();
    makeContainer();
    await pumpEventQueue();

    expect(session.refreshUserCalls, 1);
  });
}
