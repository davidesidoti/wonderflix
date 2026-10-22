import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/inbox/inbox_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  ProviderContainer container(
      {SocialFeatures features = const SocialFeatures(inbox: true)}) {
    final c = ProviderContainer.test(
        overrides:
            socialTestOverrides(api, events: events.stream, features: features));
    c.listen(inboxControllerProvider, (_, _) {});
    return c;
  }

  int loads() => api.calls.where((call) => call == 'inbox').length;

  test('senza la funzione: vuota, nessuna chiamata', () async {
    final c = container(features: SocialFeatures.none);
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(api.calls, isEmpty);
  });

  test('legge alla nascita, a ogni InboxChanged e a ogni connessione del '
      'WebSocket, la prima compresa', () async {
    api.inboxSnapshot = InboxSnapshot(entries: [testAnnouncement()], unread: 1);
    final c = container();
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).loaded, isTrue);
    expect(c.read(inboxControllerProvider).unread, 1);
    expect(loads(), 1);

    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(loads(), 2);
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(loads(), 3);
    // Anche la prima connessione rilegge: un InboxChanged mandato tra la prima
    // lettura e il WebSocket aperto altrimenti andrebbe perso.
    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(loads(), 4);
  });

  test('pannello aperto: le non lette diventano lette e prendono il pallino',
      () async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ], unread: 1);
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);

    controller.panelOpened();
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(c.read(inboxControllerProvider).highlighted, {'i1'});
    await pumpEventQueue();
    expect(api.calls, contains('read 2'));

    // Il plugin ora dice tutto letto: il pallino resta finché il pannello è
    // aperto.
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2, read: true),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ]);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).highlighted, {'i1'});

    // Una voce nuova a pannello aperto: pallino e subito letta.
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'a2', seq: 3),
      testInvite(id: 'i1', seq: 2, read: true),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ], unread: 1);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(c.read(inboxControllerProvider).highlighted, {'i1', 'a2'});
    expect(api.calls, contains('read 3'));

    controller.panelClosed();
    expect(c.read(inboxControllerProvider).highlighted, isEmpty);

    // A pannello chiuso le voci nuove restano non lette.
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'a3', seq: 4),
      testAnnouncement(id: 'a2', seq: 3, read: true),
    ], unread: 1);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).unread, 1);
    expect(api.calls, isNot(contains('read 4')));
  });

  test('Rimuovi e Svuota si vedono subito; se non riescono si rilegge',
      () async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1),
    ], unread: 2);
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);

    expect(await controller.remove('i1'), isNull);
    expect(c.read(inboxControllerProvider).snapshot.entries.map((e) => e.id),
        ['a1']);
    expect(c.read(inboxControllerProvider).unread, 1);
    expect(api.calls, contains('remove-entry i1'));

    api.nextFailure = SocialFailure.network;
    final cleared = controller.clear();
    expect(c.read(inboxControllerProvider).snapshot.entries, isEmpty);
    expect(await cleared, SocialFailure.network);
    await pumpEventQueue();
    // Il plugin ha ancora tutte e due le voci: si rilegge.
    expect(c.read(inboxControllerProvider).snapshot.entries, hasLength(2));
  });

  test('un caricamento non riuscito lo segna; Riprova rilegge', () async {
    api.nextFailure = SocialFailure.network;
    final c = container();
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).failed, isTrue);
    expect(c.read(inboxControllerProvider).loaded, isFalse);

    await c.read(inboxControllerProvider.notifier).reload();
    expect(c.read(inboxControllerProvider).failed, isFalse);
    expect(c.read(inboxControllerProvider).loaded, isTrue);
  });

  test('una risposta lenta non vale dopo una più recente', () async {
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);
    final gate = api.inboxGate = Completer<void>();
    api.inboxSnapshot =
        InboxSnapshot(entries: [testAnnouncement(id: 'old')], unread: 1);
    final slow = controller.reload();
    api.inboxGate = null;
    api.inboxSnapshot =
        InboxSnapshot(entries: [testAnnouncement(id: 'new')], unread: 1);
    await controller.reload();

    gate.complete();
    await slow;

    expect(c.read(inboxControllerProvider).snapshot.entries.single.id, 'new');
  });

  test('Rimuovi riuscita: si rilegge, la risposta lenta di prima non vale',
      () async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1),
    ], unread: 2);
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);

    // Una lettura lenta porta una voce nuova (il plugin avvisa una volta
    // sola: se la sua risposta si perdesse, la voce non arriverebbe più).
    final gate = api.inboxGate = Completer<void>();
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'n1', seq: 3),
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1),
    ], unread: 3);
    final slow = controller.reload();
    api.inboxGate = null;
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'n1', seq: 3),
      testAnnouncement(id: 'a1', seq: 1),
    ], unread: 2);

    expect(await controller.remove('i1'), isNull);
    await pumpEventQueue();
    gate.complete();
    await slow;
    await pumpEventQueue();

    expect(c.read(inboxControllerProvider).snapshot.entries.map((e) => e.id),
        ['n1', 'a1']);
    expect(loads(), 3, reason: 'si rilegge anche dopo un\'azione riuscita');
  });

  test('pannello aperto prima del primo caricamento: all\'arrivo pallini e '
      'lettura', () async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1, read: true),
      testAnnouncement(id: 'a0', seq: 0),
    ], unread: 2);
    final gate = api.inboxGate = Completer<void>();
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);

    controller.panelOpened();
    expect(c.read(inboxControllerProvider).loaded, isFalse);
    expect(c.read(inboxControllerProvider).highlighted, isEmpty);
    expect(api.calls, isNot(contains('read 2')));

    gate.complete();
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).loaded, isTrue);
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(c.read(inboxControllerProvider).highlighted, {'i1', 'a0'});
    expect(api.calls, contains('read 2'));
  });

  test('una lettura partita a pannello aperto che finisce dopo la chiusura: '
      'niente lettura, il numero resta', () async {
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);
    controller.panelOpened();
    await pumpEventQueue();
    api.calls.clear();

    final gate = api.inboxGate = Completer<void>();
    api.inboxSnapshot =
        InboxSnapshot(entries: [testAnnouncement(id: 'a2', seq: 3)], unread: 1);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(api.calls, ['inbox'], reason: 'la lettura è partita');

    controller.panelClosed();
    gate.complete();
    await pumpEventQueue();

    expect(c.read(inboxControllerProvider).unread, 1);
    expect(c.read(inboxControllerProvider).highlighted, isEmpty);
    expect(api.calls, ['inbox'], reason: 'nessun "read", il pannello è chiuso');
  });

  test('una lettura segnata non riuscita si ignora; la prossima ci riprova',
      () async {
    api.inboxSnapshot =
        InboxSnapshot(entries: [testInvite(id: 'i1', seq: 2)], unread: 1);
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);
    api.calls.clear();

    // La prima chiamata dopo l'apertura è proprio "read".
    api.nextFailure = SocialFailure.network;
    controller.panelOpened();
    await pumpEventQueue();
    expect(api.calls.first, 'read 2');
    expect(c.read(inboxControllerProvider).failed, isFalse);
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(c.read(inboxControllerProvider).highlighted, {'i1'});

    api.calls.clear();
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'a2', seq: 3),
      testInvite(id: 'i1', seq: 2, read: true),
    ], unread: 1);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(api.calls, ['inbox', 'read 3']);
    expect(c.read(inboxControllerProvider).highlighted, {'i1', 'a2'});
  });

  group('cambio utente', () {
    FakeSessionController session(ProviderContainer c) =>
        c.read(sessionControllerProvider.notifier) as FakeSessionController;

    test('a pannello aperto: niente pallini né letture per il nuovo utente',
        () async {
      api.inboxSnapshot =
          InboxSnapshot(entries: [testInvite(id: 'i1', seq: 2)], unread: 1);
      final c = container();
      await pumpEventQueue();
      c.read(inboxControllerProvider.notifier).panelOpened();
      await pumpEventQueue();
      expect(c.read(inboxControllerProvider).highlighted, {'i1'});
      api.calls.clear();

      session(c)
          .set(const SessionSignedIn(JellyfinUser(id: 'u5', name: 'Toad')));
      await pumpEventQueue();

      expect(c.read(inboxControllerProvider).highlighted, isEmpty);
      expect(c.read(inboxControllerProvider).unread, 1);
      expect(api.calls, ['inbox'], reason: 'nessuna lettura segnata');
    });

    test('stesso utente (la funzione va e viene): il pannello resta aperto',
        () async {
      api.inboxSnapshot =
          InboxSnapshot(entries: [testInvite(id: 'i1', seq: 2)], unread: 1);
      final c = container();
      await pumpEventQueue();
      c.read(inboxControllerProvider.notifier).panelOpened();
      await pumpEventQueue();
      api.calls.clear();

      final features =
          c.read(socialAvailabilityProvider.notifier) as FakeSocialAvailability;
      features.set(SocialFeatures.none);
      await pumpEventQueue();
      expect(c.read(inboxControllerProvider).unread, 0);
      expect(api.calls, isEmpty);

      api.inboxSnapshot = InboxSnapshot(entries: [
        testAnnouncement(id: 'a2', seq: 3),
        testInvite(id: 'i1', seq: 2, read: true),
      ], unread: 1);
      features.set(const SocialFeatures(inbox: true));
      await pumpEventQueue();

      // Il pannello è ancora aperto: la voce nuova ha il pallino ed è letta.
      expect(c.read(inboxControllerProvider).highlighted, {'a2'});
      expect(c.read(inboxControllerProvider).unread, 0);
      expect(api.calls, ['inbox', 'read 3']);
    });
  });
}
