import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi api;
  late FakeSyncPlayApi syncPlay;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    syncPlay = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    syncPlay.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  /// Cinque minuti fa: l'ora relativa è "5 min fa" qualunque sia il giorno
  /// della prova.
  DateTime fiveMinutesAgo() =>
      clock.now().toUtc().subtract(const Duration(minutes: 5));

  Future<void> pumpPanel(WidgetTester tester,
      {List<GroupInfo> parties = const []}) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: InboxPanel.width, child: InboxPanel()),
        ),
      ),
      overrides: [
        ...socialTestOverrides(api,
            events: events.stream,
            features: const SocialFeatures(parties: true, inbox: true)),
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory(parties)),
        syncPlayApiProvider.overrideWithValue(syncPlay),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
      ],
    );
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));

  testWidgets('vuota: "Nessuna notifica", niente Svuota', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Notifiche'), findsOneWidget);
    expect(find.text('Nessuna notifica'), findsOneWidget);
    expect(find.text('Svuota'), findsNothing);
  });

  testWidgets('caricamento non riuscito: "Notifiche non disponibili" e Riprova',
      (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpPanel(tester);
    expect(find.text('Notifiche non disponibili'), findsOneWidget);

    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stasera manutenzione'), findsOneWidget);
  });

  testWidgets('annuncio: etichetta, testo, ora; la × compare al passaggio e '
      'toglie la voce', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    expect(find.text('Annuncio'), findsOneWidget);
    expect(find.text('Stasera manutenzione'), findsOneWidget);
    expect(find.text('5 min fa'), findsOneWidget);

    Opacity removeOpacity() => tester.widget<Opacity>(find
        .ancestor(of: find.byTooltip('Rimuovi'), matching: find.byType(Opacity))
        .first);
    expect(removeOpacity().opacity, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Annuncio')));
    await tester.pump();
    expect(removeOpacity().opacity, 1);

    // Il plugin, dopo la rimozione, restituisce la cassetta senza la voce
    // (la rilettura dopo l'azione la rimette a posto).
    api.inboxSnapshot = InboxSnapshot.empty;
    await tester.tap(find.byTooltip('Rimuovi'));
    await tester.pump();
    expect(api.calls, contains('remove-entry a1'));
    expect(find.text('Stasera manutenzione'), findsNothing);
  });

  testWidgets('× non riuscita: lo dice', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    api.nextFailure = SocialFailure.network;
    await tester.tap(find.byTooltip('Rimuovi'));
    await tester.pumpAndSettle();
    expect(find.text('Non è stato possibile aggiornare le notifiche'),
        findsOneWidget);
  });

  testWidgets('invito: Unisciti se il party è nell\'elenco, altrimenti '
      '"Party finito"', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
      testInvite(
          id: 'i2',
          groupId: 'g2',
          title: 'Alien',
          createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester, parties: [testGroup()]);
    expect(find.text('Luigi ti invita a guardare'), findsNWidgets(2));
    expect(find.text('Dune'), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i1')), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i2')), findsNothing);
    expect(find.text('Party finito'), findsOneWidget);
  });

  testWidgets('invito: Unisciti entra e chiude il pannello; poi "Ci sei già"',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester, parties: [testGroup()]);
    final container = containerOf(tester);
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();

    await tester.tap(find.byKey(const Key('inbox-join-i1')));
    await tester.pumpAndSettle();
    expect(syncPlay.calls, contains('join g1'));
    expect(container.read(shellPanelProvider), ShellPanel.none);
    expect(find.text('Ci sei già'), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i1')), findsNothing);

    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('pallino dorato sulle voci non lette all\'apertura',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'a2', seq: 2, createdAt: fiveMinutesAgo()),
      testAnnouncement(
          id: 'a1', seq: 1, read: true, createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester);
    final container = containerOf(tester);
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('inbox-unread-a2')), findsOneWidget);
    expect(find.byKey(const Key('inbox-unread-a1')), findsNothing);
    expect(api.calls, contains('read 2'));
  });

  testWidgets('Svuota → Conferma per 4 s; Conferma svuota', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);

    await tester.tap(find.text('Svuota'));
    await tester.pump();
    expect(find.text('Conferma'), findsOneWidget);
    await tester.pump(InboxPanel.clearConfirmFor);
    expect(find.text('Svuota'), findsOneWidget);

    await tester.tap(find.text('Svuota'));
    await tester.pump();
    // Il plugin, dopo lo svuotamento, restituisce la cassetta vuota (la
    // rilettura dopo l'azione la rimette a posto).
    api.inboxSnapshot = InboxSnapshot.empty;
    await tester.tap(find.text('Conferma'));
    await tester.pump();
    expect(api.calls, contains('clear-inbox'));
    expect(find.text('Nessuna notifica'), findsOneWidget);
  });
}
