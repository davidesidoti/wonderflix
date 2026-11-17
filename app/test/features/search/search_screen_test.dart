import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/search/search_controller.dart'
    show searchControllerProvider;
import 'package:wonderflix/features/search/search_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('scrive, attende e mostra i risultati per sezione', (tester) async {
    final api = FakeLibraryApi()
      ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
          ? pageOf([testItem(id: 'm1', name: 'Dune')])
          : pageOf([]))
      ..people = [];
    await pumpApp(tester, const Scaffold(body: SearchScreen()), overrides: [
      libraryApiProvider.overrideWithValue(api),
      requestsAvailableProvider.overrideWithValue(false),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);

    expect(find.text('Titolo, attore o regista'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Dune'), findsNWidgets(2)); // miglior risultato e card
    expect(find.text('Miglior risultato'), findsOneWidget);
    expect(find.text('Serie'), findsNothing);
  });

  testWidgets("i dati delle persone non fanno ripartire l'entrata delle carte",
      (tester) async {
    final facts = Completer<void>();
    final api = FakeLibraryApi()
      ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
          ? pageOf([
              for (var i = 0; i < 3; i++) testItem(id: 'm$i', name: 'Dune $i'),
            ])
          : pageOf([]))
      ..people = [
        testItem(id: 'p1', name: 'Denis Villeneuve', kind: ItemKind.person),
      ]
      ..itemsGateFor = ((query) => query.personId != null ? facts : null);
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        motion: MotionLevel.full,
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          requestsAvailableProvider.overrideWithValue(false),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ]);
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    double entrance() => tester
        .widget<EntranceTransition>(find
            .descendant(
                of: find.byType(BatchedEntranceItem).first,
                matching: find.byType(EntranceTransition))
            .first)
        .progress
        .value;
    expect(entrance(), 1);

    facts.complete();
    await tester.pump();
    await tester.pump();
    expect(entrance(), 1);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('nessun risultato', (tester) async {
    final api = FakeLibraryApi();
    await pumpApp(tester, const Scaffold(body: SearchScreen()), overrides: [
      libraryApiProvider.overrideWithValue(api),
      requestsAvailableProvider.overrideWithValue(false),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(
        find.text("Nessun titolo per “zzz”. Controlla l'ortografia o prova "
            'col titolo originale.'),
        findsOneWidget);
  });

  List<Override> overrides(FakeLibraryApi library, FakeRequestsApi requests,
          {bool available = true}) =>
      [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...requestsTestOverrides(requests, available: available),
      ];

  FakeLibraryApi libraryWithDune() => FakeLibraryApi()
    ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
        ? pageOf([testItem(id: 'ee39bef06f503dd0e9dbd20593df417f', name: 'Dune')])
        : pageOf([]))
    ..people = [];

  Future<void> search(WidgetTester tester, String term) async {
    await tester.enterText(find.byType(TextField), term);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('"Da richiedere" sotto i risultati, senza i titoli già in libreria',
      (tester) async {
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [
        testRequestable(
            tmdbId: 438631,
            title: 'Dune',
            status: TitleStatus.available,
            jellyfinItemId: 'ee39bef06f503dd0e9dbd20593df417f'),
        testRequestable(tmdbId: 693134, title: 'Dune - Parte due'),
        testRequestable(
            tmdbId: 90228,
            title: 'Dune: Prophecy',
            type: RequestMediaType.tv,
            status: TitleStatus.pending),
      ];
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests));

    await search(tester, 'dune');

    expect(find.text('Da richiedere'), findsOneWidget);
    expect(find.text('Dune - Parte due'), findsOneWidget);
    expect(find.text('Dune: Prophecy'), findsOneWidget);
    expect(find.text('Richiesto'), findsOneWidget);
    expect(find.text('Film · 2024'), findsOneWidget);
    expect(find.text('Serie · 2024'), findsOneWidget);
    // Dune c'è due volte, nella libreria: miglior risultato e card.
    expect(find.text('Dune'), findsNWidgets(2));
    expect(requests.searchLanguages, ['it']);
  });

  testWidgets(
      '"Da richiedere" nasconde il titolo che la libreria ha, dall\'id TMDB '
      'anche se Seerr non conosce l\'id Jellyfin', (tester) async {
    // Dopo la scansione della notte Seerr non ha ancora l'id Jellyfin dei
    // titoli nuovi: li riconosce solo l'id TMDB dei risultati della libreria.
    final library = FakeLibraryApi()
      ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
          ? pageOf([
              testItem(id: 'aaa', name: 'Dune - Parte due', tmdbId: 693134),
            ])
          : pageOf([]))
      ..people = [];
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [
        testRequestable(tmdbId: 693134, title: 'Dune - Parte due'),
        testRequestable(
            tmdbId: 90228, title: 'Dune: Prophecy', type: RequestMediaType.tv),
      ];
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(library, requests));

    await search(tester, 'dune');

    expect(find.byKey(const ValueKey('requestable-movie-693134')), findsNothing);
    // Dune - Parte due solo dalla libreria: miglior risultato e card.
    expect(find.text('Dune - Parte due'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('requestable-tv-90228')), findsOneWidget);
    expect(find.text('Dune: Prophecy'), findsOneWidget);
  });

  testWidgets('Seerr giù: messaggio e Riprova, la libreria resta', (tester) async {
    final requests = FakeRequestsApi()..failure = RequestsFailure.seerrUnavailable;
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests));

    await search(tester, 'dune');

    expect(find.text('Seerr non risponde'), findsOneWidget);
    expect(find.text('Dune'), findsNWidgets(2));

    requests
      ..failure = null
      ..searchResults['dune'] = [testRequestable(title: 'Dune - Parte due')];
    await tester.ensureVisible(find.text('Riprova'));
    await tester.pump();
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Seerr non risponde'), findsNothing);
    expect(find.text('Dune - Parte due'), findsOneWidget);
  });

  testWidgets('senza titoli da richiedere la sezione non c\'è', (tester) async {
    final requests = FakeRequestsApi();
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests));

    await search(tester, 'dune');

    expect(find.text('Da richiedere'), findsNothing);
    expect(requests.calls, ['search:dune']);
  });

  testWidgets('senza la funzione: niente sezione e niente Seerr', (tester) async {
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [testRequestable()];
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests, available: false));

    await search(tester, 'dune');

    expect(find.text('Da richiedere'), findsNothing);
    expect(requests.calls, isEmpty);
  });

  testWidgets(
      '"Da richiedere" resta viva anche quando la sezione è fuori dallo schermo',
      (tester) async {
    // Tanti risultati della libreria: la sezione sta sotto, fuori dalla
    // zona costruita della lista, e senza ascoltatori il controller sparirebbe.
    final library = FakeLibraryApi()
      ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
          ? pageOf([
              for (var i = 0; i < 24; i++)
                testItem(id: 'movie$i', name: 'Dune $i'),
            ])
          : pageOf([
              for (var i = 0; i < 24; i++)
                testItem(
                    id: 'series$i', name: 'Arrakis $i', kind: ItemKind.series),
            ]))
      ..people = [];
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [
        testRequestable(tmdbId: 693134, title: 'Dune - Parte due'),
      ];
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(library, requests));

    await search(tester, 'dune');
    await tester.scrollUntilVisible(
        find.text('Da richiedere'), 500,
        scrollable: find.byType(Scrollable).first);

    expect(find.text('Dune - Parte due'), findsOneWidget);
    expect(requests.calls, ['search:dune']);
  });

  testWidgets(
      'se la funzione arriva dopo aver scritto, la ricerca parte da sola',
      (tester) async {
    // La funzione si può sapere tardi (il controllo del plugin ritenta dopo
    // 30 secondi): si parte spenta e poi si accende.
    final availability =
        FakeSocialAvailability(const SocialFeatures(inbox: true));
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [testRequestable(title: 'Dune - Parte due')];
    await pumpApp(tester, const Scaffold(body: SearchScreen()), overrides: [
      libraryApiProvider.overrideWithValue(libraryWithDune()),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      sharedPreferencesProvider.overrideWithValue(prefs),
      requestsApiProvider.overrideWithValue(requests),
      socialAvailabilityProvider.overrideWith(() => availability),
    ]);

    await search(tester, 'dune');
    expect(find.text('Da richiedere'), findsNothing);
    expect(requests.calls, isEmpty);

    availability.set(const SocialFeatures(inbox: true, requests: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Da richiedere'), findsOneWidget);
    expect(find.text('Dune - Parte due'), findsOneWidget);
    expect(requests.searchLanguages, ['it']);
  });

  testWidgets(
      'nuovo termine: finché Seerr non risponde, lo scheletro e non i titoli vecchi',
      (tester) async {
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [testRequestable(title: 'Dune - Parte due')]
      ..searchResults['dunes'] = [
        testRequestable(tmdbId: 1, title: 'Dunes of Mars'),
      ];
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests));

    await search(tester, 'dune');
    expect(find.text('Dune - Parte due'), findsOneWidget);
    expect(find.byKey(const ValueKey('requestables-skeleton')), findsNothing);

    // Seerr è trattenuto: la libreria risponde, Seerr no.
    final gate = requests.searchGate = Completer<void>();
    await search(tester, 'dunes');

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Dune - Parte due'), findsNothing);
    expect(find.byKey(const ValueKey('requestables-skeleton')), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('requestables-skeleton')), findsNothing);
    expect(find.text('Dunes of Mars'), findsOneWidget);
    expect(find.text('Dune - Parte due'), findsNothing);
  });

  group('saghe (spec K §8.5)', () {
    late FakeCollectionsApi collections;

    setUp(() {
      collections = FakeCollectionsApi()
        ..collectionsList = [
          testCollection(id: 'c1', name: 'Mátrix - Collezione'),
          testCollection(id: 'c2', name: 'Alien - Collezione'),
        ];
    });

    Future<void> pumpSearch(WidgetTester tester, FakeLibraryApi api) async {
      await pumpApp(tester, const Scaffold(body: SearchScreen()), overrides: [
        libraryApiProvider.overrideWithValue(api),
        requestsAvailableProvider.overrideWithValue(false),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        sharedPreferencesProvider.overrideWithValue(prefs),
        socialAvailabilityProvider.overrideWith(() =>
            FakeSocialAvailability(const SocialFeatures(collections: true))),
        collectionsApiProvider.overrideWithValue(collections),
      ]);
    }

    testWidgets('senza badare a maiuscole e accenti, sopra i film',
        (tester) async {
      final api = FakeLibraryApi()
        ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
            ? pageOf([testItem(id: 'm1', name: 'Matrix')])
            : pageOf([]))
        ..people = [];
      await pumpSearch(tester, api);
      // L'elenco si legge all'apertura, prima di scrivere.
      expect(collections.calls, 1);
      await tester.enterText(find.byType(TextField), 'MATRIX');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Saghe'), findsOneWidget);
      expect(find.text('Mátrix - Collezione'), findsOneWidget);
      expect(find.text('Alien - Collezione'), findsNothing);
      expect(tester.getTopLeft(find.text('Saghe')).dy,
          lessThan(tester.getTopLeft(find.text('Film')).dy));
      expect(collections.calls, 1);

      // Un altro termine usa l'elenco già in cache, senza rileggerlo.
      await tester.enterText(find.byType(TextField), 'alien');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Alien - Collezione'), findsOneWidget);
      expect(find.text('Mátrix - Collezione'), findsNothing);
      expect(collections.calls, 1);
    });

    testWidgets('solo saghe: niente "Nessun risultato"', (tester) async {
      await pumpSearch(tester, FakeLibraryApi());
      await tester.enterText(find.byType(TextField), 'alien');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Alien - Collezione'), findsOneWidget);
      expect(
          find.text("Nessun titolo per “alien”. Controlla l'ortografia o "
              'prova col titolo originale.'),
          findsNothing);
    });

    testWidgets('niente saghe che corrispondono: nessuna sezione',
        (tester) async {
      await pumpSearch(tester, FakeLibraryApi());
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Saghe'), findsNothing);
      expect(
          find.text(
              "Nessun titolo per “zzz”. Controlla l'ortografia o prova "
              'col titolo originale.'),
          findsOneWidget);
    });
  });

  group('campo e Invio', () {
    late FakeLibraryApi api;
    late GoRouter router;

    setUp(() {
      api = FakeLibraryApi()
        ..onItems = ((query, start, limit) => switch (query.searchTerm) {
              'dun' => query.kinds.contains(ItemKind.movie)
                  ? pageOf([testItem(id: 'dune', name: 'Dune')])
                  : pageOf([]),
              'dark' => query.kinds.contains(ItemKind.series)
                  ? pageOf([
                      testItem(id: 'dark', name: 'Dark', kind: ItemKind.series),
                    ])
                  : pageOf([]),
              'ist' => query.kinds.contains(ItemKind.series)
                  ? pageOf([
                      testItem(
                          id: 'ist', name: "L'Istituto", kind: ItemKind.series),
                    ])
                  : pageOf([]),
              _ => pageOf([]),
            })
        ..people = [];
      router = GoRouter(initialLocation: '/search', routes: [
        GoRoute(
            path: '/search',
            builder: (_, _) => const Scaffold(body: SearchScreen())),
        GoRoute(path: '/item/:id', builder: (_, _) => const SizedBox()),
      ]);
    });

    String location() => router.state.uri.toString();
    List<String>? saved() => prefs.getStringList('search.recent.${testUser.id}');

    Future<void> pumpSearch(WidgetTester tester) async {
      await pumpAppRouter(tester, router, overrides: [
        libraryApiProvider.overrideWithValue(api),
        requestsAvailableProvider.overrideWithValue(false),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      await tester.pump();
    }

    Future<void> type(WidgetTester tester, String term) async {
      await tester.enterText(find.byType(TextField), term);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    Future<void> enter(WidgetTester tester) async {
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    String fieldText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;
    bool fieldFocused(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

    testWidgets('✕ ed Esc svuotano e il campo resta col focus', (tester) async {
      await pumpSearch(tester);
      expect(find.byTooltip('Svuota'), findsNothing);

      await type(tester, 'dun');
      expect(find.byTooltip('Svuota'), findsOneWidget);
      await tester.tap(find.byTooltip('Svuota'));
      await tester.pump();
      expect(fieldText(tester), '');
      expect(fieldFocused(tester), isTrue);
      expect(find.byTooltip('Svuota'), findsNothing);
      expect(find.text('Dune'), findsNothing);

      await type(tester, 'dun');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(fieldText(tester), '');
      expect(fieldFocused(tester), isTrue);
    });

    testWidgets('Invio salva il termine e apre il miglior risultato',
        (tester) async {
      await pumpSearch(tester);
      await type(tester, 'ist');
      await enter(tester);

      expect(location(), '/item/ist');
      expect(saved(), ['ist']);
    });

    testWidgets('Invio prima dei 300 ms apre il miglior risultato del termine '
        'nuovo', (tester) async {
      await pumpSearch(tester);
      await type(tester, 'dun');
      expect(find.text('Dune'), findsNWidgets(2));

      await tester.enterText(find.byType(TextField), 'dark');
      await enter(tester);

      expect(location(), '/item/dark');
      expect(saved(), ['dark']);
    });

    testWidgets('Invio mentre carica apre il miglior risultato del termine '
        'nuovo', (tester) async {
      await pumpSearch(tester);
      await type(tester, 'dun');
      final gate = Completer<void>();
      api.itemsGateFor = (query) => query.searchTerm == 'dark' ? gate : null;

      await type(tester, 'dark');
      await enter(tester);
      expect(location(), '/search');

      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(location(), '/item/dark');
    });

    testWidgets('Invio su un termine nuovo senza miglior risultato non apre '
        'niente', (tester) async {
      await pumpSearch(tester);
      await type(tester, 'dun');

      await tester.enterText(find.byType(TextField), 'zzz');
      await enter(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(location(), '/search');
      expect(saved(), ['zzz']);
    });

    testWidgets('Invio su un errore non apre niente dopo Riprova',
        (tester) async {
      api.error = Exception('giù');
      await pumpSearch(tester);
      await type(tester, 'ist');
      expect(find.text('Riprova'), findsOneWidget);

      await enter(tester);
      api.error = null;
      await tester.tap(find.text('Riprova'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text("L'Istituto"), findsWidgets);
      expect(location(), '/search');
    });

    testWidgets('scrivere senza aprire nulla non salva', (tester) async {
      await pumpSearch(tester);
      await type(tester, 'dun');
      expect(saved(), isNull);
    });
  });

  group('risultati (spec §8.2)', () {
    late GoRouter router;

    setUp(() {
      router = GoRouter(initialLocation: '/search', routes: [
        GoRoute(
            path: '/search',
            builder: (_, _) => const Scaffold(body: SearchScreen())),
        GoRoute(path: '/item/:id', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/movies', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/series', builder: (_, _) => const SizedBox()),
        GoRoute(
            path: '/tmdb/:type/:id', builder: (_, _) => const SizedBox()),
      ]);
    });

    String location() => router.state.uri.toString();

    /// Film: 15 di totale, 7 in risposta; serie: tre, tutte in risposta.
    FakeLibraryApi libraryForIst() => FakeLibraryApi()
      ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
          ? pageOf([
              testItem(id: 'm0', name: 'Il mistero della pietra'),
              for (var i = 1; i < 7; i++)
                testItem(id: 'm$i', name: 'Cristallo $i'),
            ], 15)
          : pageOf([
              testItem(id: 's0', name: "L'Istituto", kind: ItemKind.series),
              testItem(
                  id: 's1', name: "Marvel's Iron Fist", kind: ItemKind.series),
              testItem(id: 's2', name: 'Mistica', kind: ItemKind.series),
            ]))
      ..people = [];

    Future<void> pumpResults(WidgetTester tester, FakeLibraryApi library,
        {FakeRequestsApi? requests,
        Size size = const Size(1280, 800),
        bool touch = false}) async {
      await pumpAppRouter(tester, router,
          surfaceSize: size,
          touch: touch,
          overrides: [
            libraryApiProvider.overrideWithValue(library),
            sessionControllerProvider.overrideWith(
                () => FakeSessionController(const SessionSignedIn(testUser))),
            sharedPreferencesProvider.overrideWithValue(prefs),
            if (requests == null)
              requestsAvailableProvider.overrideWithValue(false)
            else
              ...requestsTestOverrides(requests),
          ]);
      await tester.pump();
    }

    Finder postersIn(String title) => find.byWidgetPredicate((w) =>
        w is PosterCard &&
        (title == 'Film'
            ? w.item.kind == ItemKind.movie
            : w.item.kind == ItemKind.series));

    testWidgets('per "ist": miglior risultato, poi Serie prima di Film, coi '
        'conteggi', (tester) async {
      await pumpResults(tester, libraryForIst());
      await search(tester, 'ist');

      expect(find.text('Miglior risultato'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Serie')).dy,
          lessThan(tester.getTopLeft(find.text('Film')).dy));
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Vedi tutti'), findsOneWidget); // solo Film è tagliata
    });

    testWidgets('Vedi tutti apre il catalogo Film con la ricerca',
        (tester) async {
      await pumpResults(tester, libraryForIst());
      await search(tester, 'ist');

      await tester.ensureVisible(find.text('Vedi tutti'));
      await tester.pump();
      await tester.tap(find.text('Vedi tutti'));
      await tester.pump();
      await tester.pump();

      expect(location(), '/movies?q=ist');
      expect(prefs.getStringList('search.recent.${testUser.id}'), ['ist']);
    });

    testWidgets('il titolo trovato per il titolo originale va in fondo e lo '
        'dice', (tester) async {
      final library = FakeLibraryApi()
        ..onItems = ((query, start, limit) =>
            query.kinds.contains(ItemKind.movie)
            ? pageOf([
                testItem(
                    id: 'm0',
                    name: 'Maleficent - Signora del male',
                    originalTitle: 'Maleficent: Mistress of Evil'),
                testItem(id: 'm1', name: 'Il mistero della pietra'),
              ])
            : pageOf([]))
        ..people = [];
      await pumpResults(tester, library);
      await search(tester, 'ist');

      final maleficent = find.text('Maleficent - Signora del male');
      expect(tester.getTopLeft(find.text('Il mistero della pietra').last).dx,
          lessThan(tester.getTopLeft(maleficent).dx));
      expect(find.text('Titolo originale: Maleficent: Mistress of Evil'),
          findsOneWidget);
    });

    testWidgets('griglia: sette colonne a 1280, nessun overflow',
        (tester) async {
      final library = FakeLibraryApi()
        ..onItems = ((query, start, limit) =>
            query.kinds.contains(ItemKind.movie)
            ? pageOf([
                for (var i = 0; i < 10; i++)
                  testItem(id: 'm$i', name: 'Dune $i'),
              ])
            : pageOf([]))
        ..people = [];
      await pumpResults(tester, library);
      await search(tester, 'dune');

      expect(postersIn('Film'), findsNWidgets(7));
      final first = tester.getTopLeft(postersIn('Film').first).dy;
      expect(tester.getTopLeft(postersIn('Film').at(6)).dy, first);
      expect(tester.takeException(), isNull);
    });

    testWidgets('telefono 390: due colonne, quattro titoli e "Vedi tutti i 15 '
        'film"', (tester) async {
      await pumpResults(tester, libraryForIst(),
          size: const Size(390, 780), touch: true);
      await search(tester, 'ist');

      final films = postersIn('Film');
      expect(films, findsNWidgets(4));
      expect(tester.getTopLeft(films.at(0)).dy,
          tester.getTopLeft(films.at(1)).dy);
      expect(tester.getTopLeft(films.at(2)).dy,
          greaterThan(tester.getTopLeft(films.at(0)).dy));
      expect(find.text('Vedi tutti i 15 film'), findsOneWidget);
      expect(find.text('Vedi tutti'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stretto a 900: una fila intera e "Vedi tutti i 15 film" in '
        'fondo', (tester) async {
      await pumpResults(tester, libraryForIst(), size: const Size(900, 800));
      await search(tester, 'ist');

      final films = postersIn('Film');
      expect(films, findsNWidgets(5)); // (900 - 32) / 196 → 5 colonne
      expect(tester.getTopLeft(films.at(4)).dy,
          tester.getTopLeft(films.at(0)).dy);
      expect(find.text('Vedi tutti i 15 film'), findsOneWidget);
      expect(find.text('Vedi tutti'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mentre affina: linea oro, risultati attenuati che non si '
        'aprono', (tester) async {
      await pumpResults(tester, libraryForIst());
      await search(tester, 'ist');
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.enterText(find.byType(TextField), 'isti');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final poster = postersIn('Serie').first;
      await tester.ensureVisible(poster);
      await tester.tap(poster, warnIfMissed: false);
      await tester.pump();
      expect(location(), '/search');

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('mentre affina, i risultati vecchi restano ordinati per il '
        'loro termine', (tester) async {
      // Per "dune" la serie (0) sta sopra il film (1); per "dunx" nessuno
      // dei due corrisponderebbe e il film andrebbe sopra.
      final library = FakeLibraryApi()
        ..onItems = ((query, start, limit) => query.searchTerm != 'dune'
            ? pageOf([])
            : query.kinds.contains(ItemKind.movie)
                ? pageOf([testItem(id: 'm0', name: 'Sabbia e dune')])
                : pageOf([
                    testItem(
                        id: 's0',
                        name: 'Dune: Prophecy',
                        kind: ItemKind.series),
                  ]))
        ..people = [];
      await pumpResults(tester, library);
      await search(tester, 'dune');
      expect(find.text('Miglior risultato'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'dunx');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Miglior risultato'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Serie')).dy,
          lessThan(tester.getTopLeft(find.text('Film')).dy));
      const empty = "Nessun titolo per “dunx”. Controlla l'ortografia o "
          'prova col titolo originale.';
      expect(find.text(empty), findsNothing);

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text(empty), findsOneWidget);
    });

    testWidgets('TV: mentre affina il focus non va sui risultati vecchi',
        (tester) async {
      await pumpAppRouter(tester, router,
          surfaceSize: const Size(960, 540),
          tv: true,
          overrides: [
            libraryApiProvider.overrideWithValue(libraryForIst()),
            sessionControllerProvider.overrideWith(
                () => FakeSessionController(const SessionSignedIn(testUser))),
            sharedPreferencesProvider.overrideWithValue(prefs),
            requestsAvailableProvider.overrideWithValue(false),
          ]);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(SearchScreen)));
      // Il nodo di TvFocusable intorno alla locandina.
      FocusNode posterNode() => Focus.of(tester.element(find
          .descendant(
              of: postersIn('Film').first, matching: find.byType(AspectRatio))
          .first));

      container.read(searchControllerProvider.notifier).setTerm('ist');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(posterNode().canRequestFocus, isTrue);

      container.read(searchControllerProvider.notifier).setTerm('isti');
      await tester.pump(const Duration(milliseconds: 100));
      expect(posterNode().canRequestFocus, isFalse);
    });

    testWidgets('nessun titolo: la frase e sotto i da richiedere',
        (tester) async {
      final requests = FakeRequestsApi()
        ..searchResults['odissea'] = [
          testRequestable(tmdbId: 1, title: 'Odissea'),
        ];
      await pumpResults(tester, FakeLibraryApi(), requests: requests);
      await search(tester, 'odissea');

      const sentence = "Nessun titolo per “odissea”. Controlla l'ortografia "
          'o prova col titolo originale.';
      expect(find.text(sentence), findsOneWidget);
      expect(find.text('Da richiedere'), findsOneWidget);
      expect(tester.getTopLeft(find.text(sentence)).dy,
          lessThan(tester.getTopLeft(find.text('Da richiedere')).dy));
    });

    testWidgets('le carte dicono Richiedi o lo stato', (tester) async {
      final requests = FakeRequestsApi()
        ..searchResults['ist'] = [
          testRequestable(tmdbId: 1, title: 'Fakt ist!'),
          testRequestable(tmdbId: 2, status: TitleStatus.pending),
          testRequestable(
              tmdbId: 3, title: 'Odissea', status: TitleStatus.processing),
          testRequestable(
              tmdbId: 4,
              type: RequestMediaType.tv,
              status: TitleStatus.partial),
          testRequestable(tmdbId: 5, status: TitleStatus.available),
        ];
      await pumpResults(tester, FakeLibraryApi(), requests: requests);
      await search(tester, 'ist');

      expect(find.text('Richiedi'), findsOneWidget);
      expect(find.text('Richiesto'), findsOneWidget);
      expect(find.text('In arrivo'), findsOneWidget);
      expect(find.text('In parte'), findsOneWidget);
      expect(
          find.text(
              "Trovati su TMDB, non ancora su WonderFlix: chiedili all'admin"),
          findsOneWidget);
      expect(find.text('Su WonderFlix'), findsNothing);
      expect(find.byKey(const ValueKey('requestable-movie-5')), findsNothing);
    });

    testWidgets('una fila sola', (tester) async {
      final requests = FakeRequestsApi()
        ..searchResults['ist'] = [
          for (var i = 1; i <= 12; i++) testRequestable(tmdbId: i, title: 'T$i'),
        ];
      await pumpResults(tester, FakeLibraryApi(), requests: requests);
      await search(tester, 'ist');

      final cards = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('requestable-movie-'));
      expect(cards, findsWidgets);
      final dys = {
        for (final e in cards.evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      };
      expect(dys, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Richiedi apre la scheda di richiesta', (tester) async {
      final requests = FakeRequestsApi()
        ..searchResults['ist'] = [testRequestable(tmdbId: 42, title: 'Fakt ist!')];
      await pumpResults(tester, FakeLibraryApi(), requests: requests);
      await search(tester, 'ist');

      await tester.tap(find.text('Richiedi'));
      await tester.pump();
      expect(location(), '/tmdb/movie/42');
      expect(prefs.getStringList('search.recent.${testUser.id}'), ['ist']);
    });

    testWidgets('la carta apre la scheda di richiesta e salva il recente',
        (tester) async {
      final requests = FakeRequestsApi()
        ..searchResults['ist'] = [testRequestable(tmdbId: 42, title: 'Fakt ist!')];
      await pumpResults(tester, FakeLibraryApi(), requests: requests);
      await search(tester, 'ist');

      await tester.tap(find.text('Fakt ist!'));
      await tester.pump();
      expect(location(), '/tmdb/movie/42');
      expect(prefs.getStringList('search.recent.${testUser.id}'), ['ist']);
    });

    testWidgets('nessun titolo nemmeno su TMDB', (tester) async {
      await pumpResults(tester, FakeLibraryApi(), requests: FakeRequestsApi());
      await search(tester, 'zzz');
      await tester.pump(const Duration(milliseconds: 500));

      expect(
          find.text('Nessun titolo per “zzz”, nemmeno su TMDB. Controlla '
              'l\'ortografia o prova col titolo originale.'),
          findsOneWidget);
    });
  });
}
