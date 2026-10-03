import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_button.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  Future<void> pumpShell(WidgetTester tester,
      {SocialFeatures features =
          const SocialFeatures(friends: true, inbox: true)}) async {
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        ...socialTestOverrides(api, events: events.stream, features: features),
        // Nessun elenco dei watch party (né timer).
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      ],
    );
    await tester.pump();
  }

  Finder badge(String text) => find.descendant(
      of: find.byKey(const Key('inbox-button')), matching: find.text(text));

  test('numero sull\'icona: oltre 99 "99+"', () {
    expect(inboxBadgeLabel(5), '5');
    expect(inboxBadgeLabel(99), '99');
    expect(inboxBadgeLabel(100), '99+');
  });

  testWidgets('senza la cassetta: niente icona', (tester) async {
    await pumpShell(tester, features: const SocialFeatures(friends: true));
    expect(find.byKey(const Key('inbox-button')), findsNothing);
  });

  testWidgets('senza accesso ai watch party: Notifiche sì, Amici no',
      (tester) async {
    await pumpShell(tester, features: const SocialFeatures(inbox: true));
    expect(find.byKey(const Key('inbox-button')), findsOneWidget);
    expect(find.byKey(const Key('friends-button')), findsNothing);
  });

  testWidgets('icona con i non letti; aprendo diventano letti; Esc e un clic '
      'fuori chiudono', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(
          seq: 3,
          createdAt: clock.now().toUtc().subtract(const Duration(minutes: 5))),
    ], unread: 1);
    await pumpShell(tester);
    await tester.pump();
    expect(badge('1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inbox-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inbox-panel')), findsOneWidget);
    expect(api.calls, contains('read 3'));
    expect(badge('1'), findsNothing);
    expect(find.byKey(const Key('inbox-unread-a1')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inbox-panel')), findsNothing);

    await tester.tap(find.byKey(const Key('inbox-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inbox-panel')), findsNothing);
  });

  testWidgets('un avviso InboxChanged aggiorna il numero', (tester) async {
    await pumpShell(tester);
    await tester.pump();
    expect(badge('1'), findsNothing);

    api.inboxSnapshot =
        InboxSnapshot(entries: [testAnnouncement()], unread: 1);
    events.add(inboxChangedReceived());
    await tester.pump();
    await tester.pump();
    expect(badge('1'), findsOneWidget);
  });

  testWidgets('un pannello alla volta: Notifiche chiude Amici',
      (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);

    // La barra è sotto lo scuro del pannello Amici: si apre Notifiche dallo
    // stato.
    ProviderScope.containerOf(tester.element(find.byType(AppShell)))
        .read(shellPanelProvider.notifier)
        .open(ShellPanel.inbox);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);
    expect(find.byKey(const Key('inbox-panel')), findsOneWidget);
  });
}
