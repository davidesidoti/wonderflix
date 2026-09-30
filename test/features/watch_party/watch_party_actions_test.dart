import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_actions.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeLibraryApi library;
  late StreamController<ServerEvent> events;
  final pilot = testItem(
      id: 'e4',
      name: 'Pilot',
      kind: ItemKind.episode,
      seriesId: 's1',
      seriesName: 'Breaking Bad');

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    library = FakeLibraryApi()
      ..seriesEpisodes['s1'] = [
        pilot,
        testItem(id: 'e5', kind: ItemKind.episode, seriesId: 's1'),
      ];
    api.onCall = (call) {
      if (call.startsWith('create') || call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> pumpButton(WidgetTester tester) => pumpApp(
        tester,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => unawaited(startWatchParty(context, ref, pilot,
                  start: const Duration(minutes: 3))),
              child: const Text('via'),
            ),
          ),
        ),
        overrides: [
          libraryApiProvider.overrideWithValue(library),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
      );

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.text('via')));

  /// Esce dal gruppo: ferma l'orologio (i suoi timer non devono restare).
  Future<void> leave(WidgetTester tester) async {
    await container(tester).read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('fuori da un gruppo: crea il gruppo con la coda della serie',
      (tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(api.calls, ['create Mario · Breaking Bad', 'queue e4,e5']);
    expect(api.queues.single.start, const Duration(minutes: 3));
    await leave(tester);
  });

  testWidgets('dentro un gruppo: solo la nuova coda', (tester) async {
    await pumpButton(tester);
    unawaited(container(tester).read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(api.calls, ['join g1', 'queue e4,e5']);
    await leave(tester);
  });

  testWidgets('coda non disponibile: avviso, nessun gruppo', (tester) async {
    library.error = const ServerUnreachableException();
    await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(find.text('Non è stato possibile avviare il watch party.'),
        findsOneWidget);
    expect(api.calls, isEmpty);
  });
}
