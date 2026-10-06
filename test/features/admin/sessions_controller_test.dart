import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
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

  test('stesso utente su due dispositivi: l\'ordine non dipende dall\'arrivo',
      () async {
    final at = DateTime.utc(2026, 10, 6, 8);
    SessionEntry anna(String id, String device,
            {NowPlaying? playing, DateTime? last}) =>
        SessionEntry(
          id: id,
          userId: 'ua',
          userName: 'Anna',
          deviceName: device,
          nowPlaying: playing,
          lastActivity: last,
        );
    final input = [
      anna('p-tv', 'TV', playing: testMovie),
      anna('p-pc', 'pc', playing: testMovie),
      anna('p-b', 'Tablet', playing: testMovie),
      anna('p-a', 'Tablet', playing: testMovie),
      anna('i-tv', 'TV', last: at),
      anna('i-pc', 'PC', last: at),
      anna('i-b', 'Tablet', last: at),
      anna('i-a', 'Tablet', last: at),
      anna('i-none-b', 'Tablet'),
      anna('i-none-a', 'Tablet'),
    ];

    Future<(List<String>, List<String>)> orderOf(
        List<SessionEntry> sessions) async {
      api.sessionsValue = sessions;
      final container = makeContainer();
      await pumpEventQueue();
      final snapshot = container.read(sessionsControllerProvider).value!;
      return (
        [for (final s in snapshot.playing) s.id],
        [for (final s in snapshot.idle) s.id],
      );
    }

    final forward = await orderOf(input);
    final backward = await orderOf(input.reversed.toList());

    expect(forward.$1, ['p-pc', 'p-a', 'p-b', 'p-tv']);
    expect(forward.$2, ['i-pc', 'i-a', 'i-b', 'i-tv', 'i-none-a', 'i-none-b']);
    expect(backward.$1, forward.$1);
    expect(backward.$2, forward.$2);
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

  test('un errore delle sessioni è un errore della scheda', () async {
    api
      ..sessionsError = const ForbiddenException()
      ..partiesValue = testParties();
    final session = FakeSessionController(const SessionSignedIn(testAdmin));
    final container = makeContainer(session: session);
    await pumpEventQueue();

    expect(container.read(sessionsControllerProvider).error,
        isA<ForbiddenException>());
    expect(container.read(sessionsControllerProvider).value, isNull);
    expect(session.refreshUserCalls, 1);
  });

  test('sessioni e party falliti insieme: vale l\'errore delle sessioni',
      () async {
    api
      ..sessionsError = const ServerUnreachableException()
      ..partiesError = const ForbiddenException();
    final session = FakeSessionController(const SessionSignedIn(testAdmin));
    final container = makeContainer(session: session);
    await pumpEventQueue();

    expect(container.read(sessionsControllerProvider).error,
        isA<ServerUnreachableException>());
    expect(session.refreshUserCalls, 0);
  });

  test('i party non si leggono: restano le sessioni, senza errore', () async {
    api
      ..sessionsValue = testSessions()
      ..partiesError = const ForbiddenException();
    final session = FakeSessionController(const SessionSignedIn(testAdmin));
    final container = makeContainer(session: session);
    await pumpEventQueue();

    final data = container.read(sessionsControllerProvider);
    expect(data.error, isNull);
    expect(data.stale, isFalse);
    expect(data.value!.playing, isNotEmpty);
    expect(data.value!.parties, isEmpty,
        reason: 'alla prima lettura non ce ne sono di prima');
    expect(session.refreshUserCalls, 0);
  });

  test('i party non si leggono più: restano quelli della lettura prima',
      () async {
    api
      ..sessionsValue = testSessions()
      ..partiesValue = testParties();
    final container = makeContainer();
    await pumpEventQueue();
    expect(container.read(sessionsControllerProvider).value!.parties,
        hasLength(1));

    api
      ..sessionsValue = [testSession('nuova', 'zoe', playing: testMovie)]
      ..partiesError = const ServerErrorException(500);
    await container.read(sessionsControllerProvider.notifier).refresh();

    final data = container.read(sessionsControllerProvider);
    expect(data.error, isNull);
    expect(data.value!.playing.map((s) => s.userName), ['zoe']);
    expect(data.value!.parties.single.name, 'Serata Lost');

    // Tornano i party: si aggiornano.
    api
      ..partiesError = null
      ..partiesValue = const [];
    await container.read(sessionsControllerProvider.notifier).refresh();
    expect(container.read(sessionsControllerProvider).value!.parties, isEmpty);
  });
}
