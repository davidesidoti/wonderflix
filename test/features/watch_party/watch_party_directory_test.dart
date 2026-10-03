import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
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

  /// Senza il plugin (funzioni già verificate): l'elenco è quello di Jellyfin.
  ProviderContainer mount() {
    final container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      socialApiProvider.overrideWithValue(FakeSocialApi()),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(SocialFeatures.none)),
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
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
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

  /// Elenco con le funzioni del plugin [features], il plugin finto [social]
  /// e gli eventi del WebSocket [events].
  ProviderContainer mountWith(
    SocialFeatures features,
    FakeSocialApi social, {
    Stream<ServerEvent> events = const Stream.empty(),
  }) {
    final container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events),
      socialApiProvider.overrideWithValue(social),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ]);
    container.listen(watchPartyDirectoryProvider, (_, _) {});
    return container;
  }

  void setFeatures(ProviderContainer container, SocialFeatures features) =>
      (container.read(socialAvailabilityProvider.notifier)
              as FakeSocialAvailability)
          .set(features);

  test('funzioni non ancora note: nessuna richiesta, né a Jellyfin né al plugin',
      () {
    fakeAsync((async) {
      final social = FakeSocialApi();
      final container = mountWith(SocialFeatures.unknown, social);
      async.flushMicrotasks();
      // Neanche il controllo periodico fa trapelare l'elenco intero.
      async.elapse(const Duration(seconds: 90));
      expect(api.calls, isEmpty);
      expect(social.calls, isEmpty);
      expect(container.read(watchPartyDirectoryProvider), isEmpty);
      container.dispose();
    });
  });

  test('note le funzioni con parties: legge solo dal plugin', () {
    fakeAsync((async) {
      final social = FakeSocialApi()
        ..partyList = [
          testGroup(id: 'g9', name: 'Mario · Up')
              .copyWithMode(PartyMode.friends),
        ];
      final container = mountWith(SocialFeatures.unknown, social);
      async.flushMicrotasks();
      setFeatures(container,
          const SocialFeatures(friends: true, parties: true));
      async.flushMicrotasks();
      expect(social.calls, ['parties']);
      expect(api.calls, isEmpty);
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g9');
      container.dispose();
    });
  });

  test('note le funzioni senza parties: legge da Jellyfin', () {
    fakeAsync((async) {
      api.groups = [testGroup()];
      final social = FakeSocialApi();
      final container = mountWith(SocialFeatures.unknown, social);
      async.flushMicrotasks();
      setFeatures(container, SocialFeatures.none);
      async.flushMicrotasks();
      expect(api.calls, ['list']);
      expect(social.calls, isEmpty);
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g1');
      container.dispose();
    });
  });

  test('l\'elenco di Jellyfin che arriva dopo il passaggio al plugin si scarta',
      () {
    fakeAsync((async) {
      final gate = api.listGate = Completer<void>();
      api.groups = [testGroup(id: 'g8', name: 'Luigi · Segreto')];
      final social = FakeSocialApi()
        ..partyList = [
          testGroup(id: 'g9', name: 'Mario · Up')
              .copyWithMode(PartyMode.public),
        ];
      final container = mountWith(SocialFeatures.none, social);
      async.flushMicrotasks();
      expect(api.calls, ['list'], reason: 'risposta ancora in viaggio');

      setFeatures(container,
          const SocialFeatures(friends: true, parties: true));
      async.flushMicrotasks();
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g9');

      gate.complete();
      async.flushMicrotasks();
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g9',
          reason: 'la risposta lenta di Jellyfin non sovrascrive il plugin');
      container.dispose();
    });
  });

  test('passando al plugin l\'elenco di Jellyfin sparisce subito', () {
    fakeAsync((async) {
      api.groups = [testGroup(id: 'g8', name: 'Luigi · Segreto')];
      final gate = Completer<void>();
      final social = FakeSocialApi()
        ..partiesGate = gate
        ..partyList = [
          testGroup(id: 'g9', name: 'Mario · Up')
              .copyWithMode(PartyMode.public),
        ];
      final container = mountWith(SocialFeatures.none, social);
      async.flushMicrotasks();
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g8');

      setFeatures(container,
          const SocialFeatures(friends: true, parties: true));
      async.flushMicrotasks();
      expect(container.read(watchPartyDirectoryProvider), isEmpty,
          reason: 'nell\'attesa del plugin non resta l\'elenco non filtrato');

      gate.complete();
      async.flushMicrotasks();
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g9');
      container.dispose();
    });
  });

  test('plugin non interrogabile: dopo il primo errore come plugin assente',
      () {
    fakeAsync((async) {
      // Nessun override del plugin: `Info` fallisce (il client HTTP non si
      // può creare) e le funzioni passano da "non note" a "nessuna".
      final container = ProviderContainer(overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ]);
      container.listen(watchPartyDirectoryProvider, (_, _) {});
      async.flushMicrotasks();
      expect(container.read(socialAvailabilityProvider), SocialFeatures.none);
      // Una lettura per il cambio di funzioni, forse una per l'avvio.
      expect(api.calls, isNotEmpty);
      expect(api.calls, everyElement('list'));
      container.dispose();
    });
  });

  test('Info senza rete al login: nessuna lettura di /SyncPlay/List', () {
    fakeAsync((async) {
      api.groups = [testGroup(id: 'g8', name: 'Luigi · Segreto')];
      final social = FakeSocialApi()
        ..install(features: {PluginFeatures.friends, PluginFeatures.parties})
        ..infoFailure = SocialFailure.network
        ..partyList = [
          testGroup(id: 'g9', name: 'Mario · Up')
              .copyWithMode(PartyMode.public),
        ];
      // Le funzioni le controlla `SocialAvailability` vera.
      final container = ProviderContainer(overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        socialApiProvider.overrideWithValue(social),
      ]);
      container.listen(watchPartyDirectoryProvider, (_, _) {});
      async.flushMicrotasks();
      // Anche con l'elenco periodico e i nuovi tentativi di `Info`.
      async.elapse(const Duration(seconds: 90));
      expect(container.read(socialAvailabilityProvider).known, isFalse);
      expect(api.calls, isEmpty,
          reason: 'l\'elenco di Jellyfin mostrerebbe i party privati');
      expect(container.read(watchPartyDirectoryProvider), isEmpty);

      // Torna la rete: l'elenco arriva dal plugin, mai da Jellyfin.
      social.infoFailure = null;
      async.elapse(SocialAvailability.retryDelay);
      expect(api.calls, isEmpty);
      expect(social.calls, contains('parties'));
      expect(container.read(watchPartyDirectoryProvider).single.id, 'g9');
      container.dispose();
    });
  });

  test('a ogni riconnessione del WebSocket rilegge l\'elenco', () {
    fakeAsync((async) {
      final events = StreamController<ServerEvent>.broadcast();
      final social = FakeSocialApi();
      final container = mountWith(SocialFeatures.none, social,
          events: events.stream);
      async.flushMicrotasks();
      expect(api.calls, ['list']);

      events.add(const ServerConnected(false));
      async.flushMicrotasks();
      expect(api.calls, ['list'], reason: 'la prima connessione non conta');

      events.add(const ServerConnected(true));
      async.flushMicrotasks();
      expect(api.calls, ['list', 'list']);
      container.dispose();
      unawaited(events.close());
    });
  });
}
