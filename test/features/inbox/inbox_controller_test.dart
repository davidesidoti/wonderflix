import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/inbox/inbox_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

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

  test('legge alla nascita, a ogni InboxChanged e a ogni riconnessione',
      () async {
    api.inboxSnapshot = InboxSnapshot(entries: [testAnnouncement()], unread: 1);
    final c = container();
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).loaded, isTrue);
    expect(c.read(inboxControllerProvider).unread, 1);

    events.add(inboxChangedReceived());
    await pumpEventQueue();
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    // La prima connessione non è una riconnessione: niente lettura in più.
    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(loads(), 3);
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
}
