import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_models.dart';
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
      {SocialFeatures features = const SocialFeatures(friends: true)}) async {
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

  testWidgets('senza la funzione amici: niente icona', (tester) async {
    await pumpShell(tester, features: SocialFeatures.none);
    expect(find.byKey(const Key('friends-button')), findsNothing);
  });

  testWidgets('icona con il numero delle richieste; apre e chiude il pannello',
      (tester) async {
    api.snapshot = FriendsSnapshot(incoming: [
      testPerson('u3', 'Peach'),
      testPerson('u4', 'Daisy'),
    ]);
    await pumpShell(tester);
    await tester.pump();
    expect(find.byKey(const Key('friends-button')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    final loads = api.calls.where((call) => call == 'friends').length;

    // Apre (e rilegge); Esc chiude solo il pannello.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);
    expect(api.calls.where((call) => call == 'friends').length, loads + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);

    // Un clic fuori chiude.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);

    // Anche la ×.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chiudi').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);
  });

  testWidgets('Esc con il menu ⋯ aperto: chiude prima il menu, poi il pannello',
      (tester) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Rimuovi dagli amici'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Rimuovi dagli amici'), findsNothing);
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);
  });

  testWidgets('richiesta in arrivo: scheda con Accetta', (tester) async {
    await pumpShell(tester);
    events.add(friendRequestReceived('u3', 'Peach'));
    await tester.pumpAndSettle();
    expect(find.text('Peach vuole essere tuo amico'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byKey(const Key('friend-request-card')),
        matching: find.text('Accetta')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('accept u3'));
    expect(find.text('Peach vuole essere tuo amico'), findsNothing);
  });
}
