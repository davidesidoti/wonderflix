import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_button.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
  });

  tearDown(() => events.close());

  Future<void> pumpButton(WidgetTester tester, List<GroupInfo> groups) =>
      pumpApp(
        tester,
        const Scaffold(
            body: Align(
                alignment: Alignment.topRight, child: WatchPartyButton())),
        overrides: [
          watchPartyDirectoryProvider
              .overrideWith(() => FakeWatchPartyDirectory(groups)),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
      );

  /// Esce dal gruppo: ferma l'orologio (i suoi timer non devono restare).
  Future<void> leave(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WatchPartyButton)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('nessun gruppo: nessun pulsante', (tester) async {
    await pumpButton(tester, const []);
    expect(find.byKey(const Key('watch-party-button')), findsNothing);
  });

  testWidgets('elenco dei gruppi e ingresso', (tester) async {
    await pumpButton(tester, [
      testGroup(state: GroupState.playing, participants: ['Mario', 'Luigi']),
    ]);
    expect(find.text('Watch party · 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('watch-party-button')));
    await tester.pumpAndSettle();
    expect(find.text('Mario · Dune'), findsOneWidget);
    expect(find.text('2 persone · In riproduzione'), findsOneWidget);
    expect(find.text('Mario, Luigi'), findsOneWidget);

    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
    await tester.tap(find.text('Unisciti'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('join g1'));
    await leave(tester);
  });

  testWidgets('gruppo non più esistente: avviso', (tester) async {
    await pumpButton(tester, [testGroup()]);
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(const SyncPlayGroupUpdated(GroupDoesNotExist('')));
      }
    };
    await tester.tap(find.byKey(const Key('watch-party-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unisciti'));
    await tester.pumpAndSettle();
    expect(find.text('Questo watch party non esiste più.'), findsOneWidget);
  });

  testWidgets('senza accesso ai watch party: nessun pulsante', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: Align(
              alignment: Alignment.topRight, child: WatchPartyButton())),
      overrides: [
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory([testGroup()])),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            const SessionSignedIn(JellyfinUser(
                id: 'u1',
                name: 'Mario',
                syncPlayAccess: SyncPlayAccess.none)))),
      ],
    );
    expect(find.byKey(const Key('watch-party-button')), findsNothing);
  });
}
