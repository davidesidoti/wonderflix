import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/admin/sessions_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakeAdminApi api;

  setUp(() => api = FakeAdminApi());

  ProviderContainer makeContainer({FakeSessionController? session}) {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(api, session: session),
      retry: (_, _) => null,
    );
    container.listen(sessionsControllerProvider, (_, _) {});
    return container;
  }

  test('chi guarda per nome, i collegati per attività, i party', () async {
    api
      ..sessionsValue = [
        testSession('a', 'zeno', playing: testMovie),
        testSession('b', 'Anna', playing: testMovie),
        testSession('c', 'vecchio', lastActivity: DateTime.utc(2026, 10, 6, 7)),
        testSession('d', 'recente', lastActivity: DateTime.utc(2026, 10, 6, 8)),
        testSession('e', 'senza ora'),
      ]
      ..partiesValue = testParties();
    final container = makeContainer();
    await pumpEventQueue();

    final snapshot = container.read(sessionsControllerProvider).value!;
    expect(snapshot.playing.map((s) => s.userName), ['Anna', 'zeno']);
    expect(snapshot.idle.map((s) => s.userName),
        ['recente', 'vecchio', 'senza ora']);
    expect(snapshot.parties.single.name, 'Serata Lost');
    expect(api.calls, containsAll(['sessions', 'parties']));
  });

  test('senza accesso ai watch party l\'elenco non si chiede', () async {
    api.sessionsValue = testSessions();
    const noParties = JellyfinUser(
      id: 'u1',
      name: 'Mario',
      isAdministrator: true,
      syncPlayAccess: SyncPlayAccess.none,
    );
    final container = makeContainer(
        session: FakeSessionController(const SessionSignedIn(noParties)));
    await pumpEventQueue();

    expect(container.read(sessionsControllerProvider).value!.parties, isEmpty);
    expect(api.count('parties'), 0);
  });

  test('un errore dei party è un errore della scheda', () async {
    api
      ..sessionsValue = testSessions()
      ..partiesError = const ForbiddenException();
    final session = FakeSessionController(const SessionSignedIn(testAdmin));
    final container = makeContainer(session: session);
    await pumpEventQueue();

    expect(container.read(sessionsControllerProvider).error,
        isA<ForbiddenException>());
    expect(session.refreshUserCalls, 1);
  });
}
