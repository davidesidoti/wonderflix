import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['m1'] = testItem(
        id: 'm1',
        name: 'Dune: Parte Due',
        overview: 'Paul Atreides si unisce ai Fremen.',
        positionTicks: 13940000000,
        playedPercentage: 20,
        people: [
          {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
          {'Id': 'p8', 'Name': 'Denis Villeneuve', 'Type': 'Director'},
        ],
        trailers: [
          {'Url': 'https://youtube.com/watch?v=x'},
        ],
      )
      ..similarItems = [testItem(id: 'm2', name: 'Arrival')];
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    // In app la schermata vive dentro lo Scaffold dell'AppShell (servono
    // Material e ScaffoldMessenger per IconButton e SnackBar).
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('titolo, trama, azioni, cast e simili', (tester) async {
    await pumpDetail(tester);
    expect(find.text('DUNE: PARTE DUE'), findsOneWidget);
    expect(find.text('Paul Atreides si unisce ai Fremen.'), findsOneWidget);
    expect(find.text('Riprendi da 23:14'), findsOneWidget);
    expect(find.text('Ricomincia'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    expect(find.text('Zendaya'), findsOneWidget);
    expect(find.text('Chani'), findsOneWidget);
    expect(find.text('Denis Villeneuve'), findsNothing,
        reason: 'il regista non è nel cast');
    expect(find.text('Simili'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
  });

  testWidgets('trailer con schema non web: nessun pulsante', (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1', trailers: [
      {'Url': 'javascript:alert(1)'},
    ]);
    await pumpDetail(tester);
    expect(find.text('DUNE: PARTE DUE'), findsOneWidget);
    expect(find.text('Trailer'), findsNothing);
  });

  testWidgets('cuore: aggiunge a La mia lista', (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byTooltip('Aggiungi a La mia lista'));
    await tester.pump();
    expect(api.favoriteCalls, [('m1', true)]);
    expect(find.byTooltip('Rimuovi da La mia lista'), findsOneWidget);
  });

  testWidgets('segna come visto', (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byTooltip('Segna come visto'));
    await tester.pump();
    expect(api.playedCalls, [('m1', true)]);
  });

  testWidgets('elemento inesistente: errore con riprova', (tester) async {
    api.itemsById.clear();
    await pumpDetail(tester);
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('solo trailer locale: pulsante presente', (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1', localTrailers: 1);
    await pumpDetail(tester);
    expect(find.text('Trailer'), findsOneWidget);
  });

  testWidgets('Guarda insieme: crea il gruppo dal punto di ripresa',
      (tester) async {
    final syncPlay = FakeSyncPlayApi();
    final events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    syncPlay.onCall = (call) {
      if (call.startsWith('create')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          syncPlayApiProvider.overrideWithValue(syncPlay),
          watchPartyEventsProvider.overrideWithValue(events.stream),
        ]);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Guarda insieme'));
    await tester.pumpAndSettle();
    expect(syncPlay.calls, ['create Mario · Dune: Parte Due', 'queue m1']);
    // positionTicks 13940000000 = 23:14.
    expect(syncPlay.queues.single.start,
        const Duration(minutes: 23, seconds: 14));

    final container = ProviderScope.containerOf(
        tester.element(find.byType(ItemDetailScreen)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('Guarda insieme su un episodio: coda con gli episodi dopo',
      (tester) async {
    final pilot = testItem(
        id: 'm1',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesId: 's1',
        seriesName: 'Breaking Bad');
    api.itemsById['m1'] = pilot;
    api.seriesEpisodes['s1'] = [
      pilot,
      testItem(id: 'e2', kind: ItemKind.episode, seriesId: 's1'),
    ];
    final syncPlay = FakeSyncPlayApi();
    final events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    syncPlay.onCall = (call) {
      if (call.startsWith('create')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          syncPlayApiProvider.overrideWithValue(syncPlay),
          watchPartyEventsProvider.overrideWithValue(events.stream),
        ]);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Guarda insieme'));
    await tester.pumpAndSettle();
    expect(syncPlay.calls, ['create Mario · Breaking Bad', 'queue m1,e2']);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(ItemDetailScreen)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('solo entrare nei watch party: niente "Guarda insieme"',
      (tester) async {
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(() => FakeSessionController(
              const SessionSignedIn(JellyfinUser(
                  id: 'u1',
                  name: 'Mario',
                  syncPlayAccess: SyncPlayAccess.joinOnly)))),
        ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprendi da 23:14'), findsOneWidget);
    expect(find.text('Guarda insieme'), findsNothing);
  });

  testWidgets('la riga "Fa parte di" sta prima di "Simili" (spec K §8.3)',
      (tester) async {
    api.itemsByCollection['c1'] = [
      testItem(id: 'm1', name: 'Dune: Parte Due'),
      testItem(id: 'm3', name: 'Dune: Messia'),
    ];
    final collections = FakeCollectionsApi()
      ..collectionsList = [
        testCollection(id: 'c1', name: 'Dune - Collezione', itemIds: ['m1', 'm3']),
      ];
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        surfaceSize: const Size(1440, 2200),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          socialAvailabilityProvider.overrideWith(() =>
              FakeSocialAvailability(const SocialFeatures(collections: true))),
          collectionsApiProvider.overrideWithValue(collections),
        ]);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final saga = find.text('Fa parte di: Dune - Collezione');
    expect(saga, findsOneWidget);
    expect(find.text('Dune: Messia'), findsOneWidget);
    expect(tester.getTopLeft(saga).dy,
        lessThan(tester.getTopLeft(find.text('Simili')).dy));
  });
}
