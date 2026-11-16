import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/core/trailers/trailers_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';
import 'package:wonderflix/ui/expandable_text.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/trailer_fakes.dart';
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
          {'Url': 'https://youtube.com/watch?v=25WcssMq1VM'},
        ],
      )
      ..similarItems = [testItem(id: 'm2', name: 'Arrival')];
  });

  Future<void> pumpDetail(WidgetTester tester,
      {List<Override> extra = const [],
      Size surfaceSize = const Size(1440, 900)}) async {
    // In app la schermata vive dentro lo Scaffold dell'AppShell (servono
    // Material e ScaffoldMessenger per IconButton e SnackBar).
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        surfaceSize: surfaceSize,
        overrides: [
      ...extra,
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
    expect(find.byTooltip('Ricomincia'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    expect(find.text('Zendaya'), findsOneWidget);
    expect(find.text('Chani'), findsOneWidget);
    expect(find.text('Denis Villeneuve'), findsNothing,
        reason: 'il regista non è nel cast');
    expect(find.text('Simili'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
  });

  /// Gruppo che si può creare, Vota e Consiglia a… con un amico.
  List<Override> allActions() {
    final social = FakeSocialApi()..install(features: const {});
    social.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    social.itemRatingsById['m1'] =
        const ItemRatings(canRate: true, count: 0, friends: []);
    return socialTestOverrides(social,
        features: const SocialFeatures(
            friends: true, ratings: true, recommendations: true),
        session: false);
  }

  testWidgets('azioni in ordine fisso e ⋯ per ultimo', (tester) async {
    await pumpDetail(tester, extra: allActions());
    final xs = [
      find.text('Riprendi da 23:14'),
      find.byTooltip('Ricomincia'),
      find.text('Guarda insieme'),
      find.text('Trailer'),
      find.byTooltip('Aggiungi a La mia lista'),
      find.byTooltip('Segna come visto'),
      find.byTooltip('Vota'),
      find.byTooltip('Consiglia a…'),
      find.byTooltip('Altre azioni'),
    ].map((f) => tester.getCenter(f).dx).toList();
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]), reason: 'azione $i');
    }
    expect(find.text('Ricomincia'), findsNothing, reason: "è un'icona");
    // 120 min − 23:14.
    expect(find.text('rimangono 1h 36m'), findsOneWidget);
  });

  testWidgets('stretto: sei azioni con la parola, Ricomincia nel ⋯',
      (tester) async {
    await pumpDetail(tester,
        extra: allActions(), surfaceSize: const Size(390, 780));
    for (final label in [
      'La mia lista',
      'Visto',
      'Trailer',
      'Insieme',
      'Consiglia',
      'Altro',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('rimangono 1h 36m'), findsOneWidget);
    expect(find.byTooltip('Ricomincia'), findsNothing);
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Ricomincia'), findsOneWidget);
    expect(find.text('Consiglia a…'), findsNothing);
  });

  testWidgets('riga oro col regista e una sola riga di dati', (tester) async {
    api.itemsById['m1'] = testItem(
      id: 'm1',
      name: 'Dune: Parte Due',
      rating: 7.5,
      genres: const ['Drama', 'Romance', 'Crime'],
      people: [
        {'Id': 'p8', 'Name': 'Denis Villeneuve', 'Type': 'Director'},
      ],
    );
    await pumpDetail(tester);
    expect(find.text('Film di Denis Villeneuve'), findsOneWidget);
    expect(find.text('2024 · 2h · Dramma · Romantico'), findsOneWidget);
    expect(find.text('7,5'), findsOneWidget);
    expect(find.text('Drama · Romance · Crime'), findsNothing);
    final title = tester.widget<Text>(find.text('DUNE: PARTE DUE'));
    expect(title.style?.fontSize, 96);
  });

  for (final (name, size, fontSize) in [
    ('stretto', const Size(390, 780), 48.0),
    ('desktop', const Size(1440, 900), 96.0),
  ]) {
    testWidgets('titolo su due righe $name: sta sopra la riga dei dati',
        (tester) async {
      api.itemsById['m1'] = testItem(
          id: 'm1',
          name: 'Il signore degli anelli la compagnia dell anello edizione '
              'estesa con scene mai viste prima',
          genres: const ['Drama']);
      await pumpDetail(tester, surfaceSize: size);
      final title = find.textContaining('IL SIGNORE DEGLI ANELLI');
      expect(tester.widget<Text>(title).style?.fontSize, fontSize);
      expect(tester.getSize(title).height, greaterThan(fontSize * 1.5),
          reason: 'il nome va a capo');
      expect(tester.getRect(title).bottom,
          lessThanOrEqualTo(tester.getRect(find.text('2024 · 2h · Dramma')).top));
    });
  }

  for (final size in [const Size(1440, 900), const Size(1280, 800)]) {
    testWidgets('trama lunghissima aperta a ${size.width.toInt()}: titolo su '
        'due righe sotto la barra, trama alta 6 righe e scorrevole',
        (tester) async {
      final long = 'Una trama lunga che va su più righe. ' * 60;
      api.itemsById['m1'] = testItem(
          id: 'm1',
          name: 'Il signore degli anelli la compagnia dell anello edizione '
              'estesa con scene mai viste prima',
          overview: long);
      await pumpDetail(tester, surfaceSize: size);
      await tester.tap(find.text('Altro'));
      await tester.pump();
      final title = find.textContaining('IL SIGNORE DEGLI ANELLI');
      expect(tester.getSize(title).height, greaterThan(96 * 1.5),
          reason: 'il nome va a capo');
      expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(shellBarHeight));
      final box = find.descendant(
          of: find.byType(ExpandableText),
          matching: find.byType(SingleChildScrollView));
      final lineHeight =
          DefaultTextStyle.of(tester.element(find.text(long))).style.fontSize! *
              1.45;
      expect(tester.getSize(box).height, lessThanOrEqualTo(6 * lineHeight));
      final position = tester
          .state<ScrollableState>(
              find.descendant(of: box, matching: find.byType(Scrollable)))
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.drag(box, const Offset(0, -5000));
      await tester.pump();
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.01));
    });
  }

  testWidgets('film senza regista: la riga oro dice solo Film', (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1', name: 'Dune: Parte Due');
    await pumpDetail(tester);
    expect(find.text('Film'), findsOneWidget);
    expect(find.textContaining('Film di'), findsNothing);
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

  testWidgets('menu "⋯": Togli da Continua a guardare, poi Annulla',
      (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Togli da Continua a guardare'));
    await tester.pumpAndSettle();
    expect(api.positionCalls, [('m1', 0)]);
    expect(api.playedCalls, isEmpty);
    expect(find.text('Riprendi da 23:14'), findsNothing);
    expect(find.text('Tolto da Continua a guardare'), findsOneWidget);
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Togli da Continua a guardare'), findsNothing,
        reason: 'senza punto di ripresa la voce non c\'è');
    await tester.tapAt(Offset.zero); // chiude il menu
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(api.positionCalls.last, ('m1', 13940000000));
    expect(find.text('Riprendi da 23:14'), findsOneWidget);
  });

  testWidgets('elemento inesistente: errore con riprova', (tester) async {
    api.itemsById.clear();
    await pumpDetail(tester);
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('trailerButtonShowsWhenThePluginHasOne', (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1');
    final trailers = FakeTrailersApi();
    await pumpDetail(tester,
        extra: [trailersApiProvider.overrideWithValue(trailers)]);
    expect(find.text('Trailer'), findsOneWidget);
    expect(trailers.availableCalls, [const LibraryTrailer('m1')]);
  });

  testWidgets('noTrailerButtonWhenThePluginIsOld', (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1');
    final trailers = FakeTrailersApi()..availableResult = false;
    await pumpDetail(tester,
        extra: [trailersApiProvider.overrideWithValue(trailers)]);
    expect(find.text('Trailer'), findsNothing);
  });

  testWidgets('trailer YouTube di Jellyfin: nessuna chiamata a Info',
      (tester) async {
    final trailers = FakeTrailersApi();
    await pumpDetail(tester,
        extra: [trailersApiProvider.overrideWithValue(trailers)]);
    expect(find.text('Trailer'), findsOneWidget);
    expect(trailers.availableCalls, isEmpty);
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
