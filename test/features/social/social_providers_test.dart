import 'dart:async';

import 'package:fake_async/fake_async.dart';
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
    expect(c.read(socialAvailabilityProvider), SocialFeatures.unknown);

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

  test('dopo il login le funzioni non sono note finché Info non risponde',
      () async {
    api.install();
    final gate = api.infoGate = Completer<void>();
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.unknown);
    expect(c.read(socialAvailabilityProvider).known, isFalse);
    expect(SocialFeatures.unknown, isNot(SocialFeatures.none));
    expect(SocialFeatures.none.known, isTrue);

    gate.complete();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(friends: true));
    expect(c.read(socialAvailabilityProvider).known, isTrue);
  });

  test('Info senza rete prima di conoscere le funzioni: restano non note',
      () async {
    api
      ..install()
      ..infoFailure = SocialFailure.network;
    final gate = api.infoGate = Completer<void>();
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.unknown);

    gate.complete();
    await pumpEventQueue();
    // Non come plugin assente: con `none` l'elenco verrebbe da
    // `/SyncPlay/List`, non filtrato, e mostrerebbe i party privati.
    expect(c.read(socialAvailabilityProvider), SocialFeatures.unknown);
  });

  test('Info senza rete: si riprova dopo 30 s finché le funzioni sono note',
      () {
    fakeAsync((async) {
      api
        ..install(features: {PluginFeatures.friends, PluginFeatures.parties})
        ..infoFailure = SocialFailure.network;
      final c = container();
      async.flushMicrotasks();
      expect(api.calls, ['info']);
      expect(c.read(socialAvailabilityProvider), SocialFeatures.unknown);

      // Ancora senza rete al primo nuovo tentativo: se ne fa un altro.
      async.elapse(SocialAvailability.retryDelay);
      expect(api.calls, ['info', 'info']);
      expect(c.read(socialAvailabilityProvider), SocialFeatures.unknown);

      api.infoFailure = null;
      async.elapse(
          SocialAvailability.retryDelay - const Duration(milliseconds: 1));
      expect(api.calls, hasLength(2));
      async.elapse(const Duration(milliseconds: 1));
      expect(api.calls, ['info', 'info', 'info']);
      expect(c.read(socialAvailabilityProvider),
          const SocialFeatures(friends: true, parties: true));

      // Note le funzioni, niente più tentativi.
      async.elapse(SocialAvailability.retryDelay * 4);
      expect(api.calls, hasLength(3));
    });
  });

  test('Info senza rete: i tentativi si fermano al cambio di utente', () {
    fakeAsync((async) {
      api
        ..install()
        ..infoFailure = SocialFailure.network;
      final c = container();
      async.flushMicrotasks();
      expect(api.calls, ['info']);

      (c.read(sessionControllerProvider.notifier) as FakeSessionController)
          .set(const SessionSignedOut());
      async.flushMicrotasks();
      expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
      async.elapse(SocialAvailability.retryDelay * 3);
      expect(api.calls, ['info']);
    });
  });

  test('404 o permesso negato: nessuna funzione, senza riprovare', () {
    for (final failure in [SocialFailure.unavailable, SocialFailure.forbidden]) {
      fakeAsync((async) {
        api = FakeSocialApi()
          ..install()
          ..infoFailure = failure;
        final c = container();
        async.flushMicrotasks();
        expect(c.read(socialAvailabilityProvider), SocialFeatures.none,
            reason: failure.name);
        async.elapse(SocialAvailability.retryDelay * 3);
        expect(api.calls, ['info'], reason: failure.name);
      });
    }
  });

  test('troppe richieste: come un errore di rete, si riprova', () {
    fakeAsync((async) {
      api
        ..install()
        ..infoFailure = SocialFailure.rateLimited;
      final c = container();
      async.flushMicrotasks();
      expect(c.read(socialAvailabilityProvider), SocialFeatures.unknown);
      api.infoFailure = null;
      async.elapse(SocialAvailability.retryDelay);
      expect(c.read(socialAvailabilityProvider),
          const SocialFeatures(friends: true));
    });
  });

  test('whenKnown: subito se note, alla risposta, o non note dopo l\'attesa',
      () {
    fakeAsync((async) {
      const wait = Duration(seconds: 2);
      api
        ..install()
        ..infoFailure = SocialFailure.network;
      final c = container();
      async.flushMicrotasks();
      final notifier = c.read(socialAvailabilityProvider.notifier);

      // Non note per tutta l'attesa.
      SocialFeatures? expired;
      unawaited(notifier.whenKnown(wait).then((f) => expired = f));
      async.elapse(wait - const Duration(milliseconds: 1));
      expect(expired, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(expired, SocialFeatures.unknown);

      // Note durante l'attesa: subito, senza aspettare la fine.
      SocialFeatures? answered;
      unawaited(notifier.whenKnown(wait).then((f) => answered = f));
      api.infoFailure = null;
      events.add(const ServerConnected(true));
      async.flushMicrotasks();
      expect(answered, const SocialFeatures(friends: true));

      // Già note: subito.
      SocialFeatures? known;
      unawaited(notifier.whenKnown(wait).then((f) => known = f));
      async.flushMicrotasks();
      expect(known, const SocialFeatures(friends: true));
      expect(async.pendingTimers, isEmpty, reason: 'nessuna attesa rimasta');
    });
  });

  test('Info senza parties né friends: funzioni note, nessuna', () async {
    api.install(features: const {});
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
    expect(c.read(socialAvailabilityProvider).known, isTrue);
  });

  // Al login partono insieme il primo controllo e quello della connessione
  // del WebSocket: una risposta riuscita vale anche se l'altro controllo
  // fallisce, in qualunque ordine partano e finiscano.
  for (final failure in [SocialFailure.network, SocialFailure.unavailable]) {
    for (final failedCheck in [0, 1]) {
      for (final failureFirst in [true, false]) {
        test(
            'controlli concorrenti: vince la risposta riuscita '
            '(${failure.name}, fallisce il controllo $failedCheck, '
            '${failureFirst ? 'prima' : 'dopo'} la risposta)', () async {
          api.manualInfo = true;
          final c = container();
          await pumpEventQueue();
          events.add(const ServerConnected(false));
          await pumpEventQueue();
          expect(api.pendingInfo, hasLength(2));

          final failing = api.pendingInfo[failedCheck];
          final succeeding = api.pendingInfo[1 - failedCheck];
          void fail() => failing.completeError(SocialException(failure));
          void succeed() => succeeding.complete(const SocialPluginInfo(
              version: '1.1.0',
              features: {PluginFeatures.friends, PluginFeatures.parties}));
          if (failureFirst) {
            fail();
            await pumpEventQueue();
            succeed();
          } else {
            succeed();
            await pumpEventQueue();
            fail();
          }
          await pumpEventQueue();

          expect(c.read(socialAvailabilityProvider),
              const SocialFeatures(friends: true, parties: true));
        });
      }
    }
  }

  test('un errore inatteso prima di conoscere le funzioni: come plugin assente',
      () async {
    final c = ProviderContainer.test(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      socialApiProvider.overrideWith((ref) => throw StateError('non pronto')),
    ]);
    c.listen(socialAvailabilityProvider, (_, _) {});
    expect(c.read(socialAvailabilityProvider), SocialFeatures.unknown);
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
  });

  test('un nuovo controllo non rimette le funzioni tra le non note', () async {
    api.install();
    final c = container();
    await pumpEventQueue();
    final gate = api.infoGate = Completer<void>();
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider).known, isTrue);
    expect(c.read(socialAvailabilityProvider).friends, isTrue);
    gate.complete();
    await pumpEventQueue();
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
