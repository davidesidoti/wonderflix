import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/wonderflix_controllers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakePluginAdminApi plugin;
  late FakeSessionController session;

  setUp(() {
    plugin = FakePluginAdminApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(FakeAdminApi(),
          plugin: plugin, session: session),
      retry: (_, _) => null,
    );
    container.listen(inboxAdminControllerProvider, (_, _) {});
    container.listen(seerrAdminControllerProvider, (_, _) {});
    return container;
  }

  test('legge novità e Seerr; un plugin vecchio non ha la card Seerr',
      () async {
    final container = makeContainer();
    await pumpEventQueue();

    expect(container.read(inboxAdminControllerProvider).value!.pending, 3);
    expect(container.read(seerrAdminControllerProvider).value!.status!.configured,
        isTrue);

    plugin.seerrValue = null;
    await container.read(seerrAdminControllerProvider.notifier).refresh();
    final data = container.read(seerrAdminControllerProvider);
    expect(data.value, isNotNull);
    expect(data.value!.status, isNull);
  });

  test('azioni: chiamano il plugin e rileggono', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final inbox = container.read(inboxAdminControllerProvider.notifier);

    expect(await inbox.announce('Ciao'), 12);
    await inbox.setNotifyNewTitles(false);
    await pumpEventQueue();
    expect(container.read(inboxAdminControllerProvider).value!.enabled, isFalse);
    final sent = await inbox.sendNewTitles();
    expect(sent.titles, 3);
    final result =
        await container.read(seerrAdminControllerProvider.notifier).test();
    expect(result.version, '3.4.1');

    expect(plugin.calls,
        containsAllInOrder(['announce:Ciao', 'notify:false', 'send', 'test']));
    expect(plugin.count('newTitles'), greaterThanOrEqualTo(3));
  });

  test('403 su un\'azione: rilegge l\'utente', () async {
    plugin.actionError = const ForbiddenException();
    final container = makeContainer();
    await pumpEventQueue();

    await expectLater(
        container.read(inboxAdminControllerProvider.notifier).sendNewTitles(),
        throwsA(isA<ForbiddenException>()));
    expect(session.refreshUserCalls, 1);
  });

  test('le due card hanno errori separati', () async {
    plugin.newTitlesError = const ServerUnreachableException();
    final container = makeContainer();
    await pumpEventQueue();

    expect(container.read(inboxAdminControllerProvider).error,
        isA<ServerUnreachableException>());
    expect(container.read(seerrAdminControllerProvider).error, isNull);
  });
}
