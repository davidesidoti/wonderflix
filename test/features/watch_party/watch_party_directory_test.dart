import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;

  setUp(() => api = FakeSyncPlayApi());

  ProviderContainer mount() {
    final container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
    ]);
    container.listen(watchPartyDirectoryProvider, (_, _) {});
    return container;
  }

  test('elenco all\'avvio e poi ogni 30 s', () {
    fakeAsync((async) {
      final container = mount();
      async.flushMicrotasks();
      expect(api.calls, ['list']);
      expect(container.read(watchPartyDirectoryProvider), isEmpty);

      api.groups = [testGroup()];
      async.elapse(const Duration(seconds: 30));
      expect(api.calls, ['list', 'list']);
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g1');
      container.dispose();
    });
  });

  test('con il player aperto non chiede nulla; all\'uscita aggiorna', () {
    fakeAsync((async) {
      final container = mount();
      async.flushMicrotasks();
      container.read(playerActiveProvider.notifier).enter();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60));
      expect(api.calls, ['list']);

      container.read(playerActiveProvider.notifier).leave();
      async.flushMicrotasks();
      expect(api.calls, ['list', 'list']);
      container.dispose();
    });
  });

  test('errore di rete: resta l\'elenco precedente', () {
    fakeAsync((async) {
      api.groups = [testGroup()];
      final container = mount();
      async.flushMicrotasks();
      api.error = const ServerUnreachableException();
      async.elapse(const Duration(seconds: 30));
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g1');
      container.dispose();
    });
  });

  test('senza accesso ai watch party: nessuna richiesta', () {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: [
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            const SessionSignedIn(JellyfinUser(
                id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)))),
        syncPlayApiProvider.overrideWithValue(api),
      ]);
      container.listen(watchPartyDirectoryProvider, (_, _) {});
      async.elapse(const Duration(minutes: 2));
      expect(api.calls, isEmpty);
      expect(container.read(watchPartyDirectoryProvider), isEmpty);
      container.dispose();
    });
  });

  test('con la funzione parties l\'elenco viene dal plugin', () {
    fakeAsync((async) {
      final social = FakeSocialApi()
        ..partyList = [
          testGroup(id: 'g9', name: 'Mario · Up')
              .copyWithMode(PartyMode.friends),
        ];
      final container = ProviderContainer(overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        syncPlayApiProvider.overrideWithValue(api),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, parties: true))),
      ]);
      container.listen(watchPartyDirectoryProvider, (_, _) {});
      async.flushMicrotasks();
      expect(social.calls, ['parties']);
      expect(api.calls, isEmpty);
      expect(container.read(watchPartyDirectoryProvider).single.mode,
          PartyMode.friends);
      container.dispose();
    });
  });
}
