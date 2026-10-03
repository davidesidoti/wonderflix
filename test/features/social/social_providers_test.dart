import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  ProviderContainer container(
      {SessionState session = const SessionSignedIn(testUser)}) {
    final c = ProviderContainer.test(overrides: [
      sessionControllerProvider.overrideWith(() => FakeSessionController(session)),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      socialApiProvider.overrideWithValue(api),
    ]);
    c.listen(socialAvailabilityProvider, (_, _) {});
    return c;
  }

  test('senza utente o senza watch party: nessuna funzione, nessuna chiamata',
      () async {
    api.install();
    final signedOut = container(session: const SessionSignedOut());
    await pumpEventQueue();
    expect(signedOut.read(socialAvailabilityProvider), SocialFeatures.none);
    final noAccess = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(noAccess.read(socialAvailabilityProvider), SocialFeatures.none);
    expect(api.calls, isEmpty);
  });

  test('Info con gli amici: funzione attiva', () async {
    api.install();
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(friends: true));
    expect(api.calls, ['info']);
  });

  test('plugin assente: nessuna funzione', () async {
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
  });

  test('a ogni connessione rilegge Info; un errore di rete non cambia nulla',
      () async {
    api.install();
    final c = container();
    await pumpEventQueue();
    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(api.calls, ['info', 'info'], reason: 'anche la prima connessione');

    api.infoFailure = SocialFailure.network;
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider).friends, isTrue);

    api
      ..infoFailure = null
      ..pluginInfo = null;
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
    expect(api.calls, ['info', 'info', 'info', 'info']);
  });

  test('un primo controllo fallito si ripete alla prima connessione',
      () async {
    api
      ..install()
      ..infoFailure = SocialFailure.network;
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);

    api.infoFailure = null;
    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(friends: true));
  });

  test('un Info lento non vale più dopo un logout', () async {
    api.install();
    final gate = api.infoGate = Completer<void>();
    final c = container();
    await pumpEventQueue();
    expect(api.calls, ['info']);

    (c.read(sessionControllerProvider.notifier) as FakeSessionController)
        .set(const SessionSignedOut());
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();

    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
  });

  test('il primo controllo non parte se l\'utente cambia prima del microtask',
      () async {
    api.install();
    final c = container();
    (c.read(sessionControllerProvider.notifier) as FakeSessionController)
        .set(const SessionSignedOut());
    // Leggere subito ricostruisce il provider prima del microtask con cui
    // `build` aveva fatto partire il primo controllo.
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
    await pumpEventQueue();

    expect(api.calls, isEmpty);
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
  });

  test('un Info lento non vale per chi entra dopo senza watch party',
      () async {
    api.install();
    final gate = api.infoGate = Completer<void>();
    final c = container();
    await pumpEventQueue();

    (c.read(sessionControllerProvider.notifier) as FakeSessionController).set(
        const SessionSignedIn(JellyfinUser(
            id: 'u5', name: 'Toad', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();

    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
    expect(api.calls, ['info'], reason: 'per il nuovo utente nessuna chiamata');
  });

  test('avvisi sociali dal WebSocket', () async {
    final c = container();
    final received = <SocialEvent>[];
    final subscription = c.read(socialEventsProvider).listen(received.add);
    addTearDown(subscription.cancel);

    events
      ..add(friendRequestReceived('u2', 'Luigi'))
      ..add(const PartyChannelReceived('{"Protocol":1,"Type":"Chat"}'))
      ..add(const ServerConnected(true))
      ..add(friendsChangedReceived());
    await pumpEventQueue();

    expect(received, hasLength(2));
    expect((received.first as FriendRequestEvent).fromName, 'Luigi');
    expect(received.last, isA<FriendsChangedEvent>());
  });
}
