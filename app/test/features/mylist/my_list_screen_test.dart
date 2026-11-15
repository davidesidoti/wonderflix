import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_band.dart';
import 'package:wonderflix/features/catalog/catalog_genre_index.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/my_list_added.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';
import 'package:wonderflix/features/mylist/my_list_view.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/skeletons.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

const _minute = 600000000;

void main() {
  /// VisionQuest serie iniziata, Parasite film nuovo, Interstellar visto.
  List<JellyfinItem> library() => [
    testItem(
      id: 'vq',
      name: 'VisionQuest',
      kind: ItemKind.series,
      favorite: true,
      recursiveCount: 10,
      unplayedCount: 5,
      playedPercentage: 50,
      dateCreated: '2024-06-01T00:00:00Z',
    ),
    testItem(
      id: 'p',
      name: 'Parasite',
      favorite: true,
      dateCreated: '2024-05-01T00:00:00Z',
    ),
    testItem(
      id: 'i',
      name: 'Interstellar',
      favorite: true,
      played: true,
      dateCreated: '2024-04-01T00:00:00Z',
    ),
  ];

  /// [n] film nuovi: "Film 00", "Film 01", ...; i pari d'Azione.
  List<JellyfinItem> many(int n) => [
    for (var i = 0; i < n; i++)
      testItem(
        id: 'f$i',
        name: 'Film ${'$i'.padLeft(2, '0')}',
        favorite: true,
        genres: [i.isEven ? 'Azione' : 'Commedia'],
        dateCreated: DateTime.utc(
          2024,
          1,
          1,
        ).add(Duration(days: i)).toIso8601String(),
      ),
  ];

  FakeLibraryApi apiWith(List<JellyfinItem> items) =>
      FakeLibraryApi()
        ..onItems = (query, start, limit) =>
            query.favoritesOnly ? pageOf(items) : pageOf([]);

  List<String> cardNames(WidgetTester tester) => [
    for (final card in tester.widgetList<PosterCard>(find.byType(PosterCard)))
      card.item.name,
  ];

  Future<GoRouter> pumpList(
    WidgetTester tester,
    FakeLibraryApi api, {
    String location = '/mylist',
    Size size = const Size(1440, 2400),
    bool tv = false,
    FakeDisplayPreferencesApi? prefs,
  }) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/mylist',
          builder: (context, state) => Scaffold(
            body: MyListScreen(
              key: const ValueKey('mylist'),
              tab: MyListTab.parse(state.uri.queryParameters['kind']),
            ),
          ),
        ),
        GoRoute(path: '/movies', builder: (_, _) => const Text('pagina film')),
        GoRoute(path: '/series', builder: (_, _) => const Text('pagina serie')),
      ],
    );
    await pumpAppRouter(
      tester,
      router,
      surfaceSize: size,
      tv: tv,
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        displayPreferencesApiProvider.overrideWithValue(
          prefs ?? FakeDisplayPreferencesApi(),
        ),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    await tester.pumpAndSettle();
    return router;
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('gruppi: VisionQuest nel cartellone e non in Da continuare', (
    tester,
  ) async {
    final api = apiWith(library());
    await pumpList(tester, api);
    expect(find.text('LA MIA LISTA'), findsOneWidget);
    expect(
      find.text(
        '3 titoli: 1 da continuare, 1 da iniziare, 1 visto.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('VisionQuest', findRichText: true),
      findsOneWidget,
    );
    // L'unico iniziato è nel cartellone.
    expect(find.text('Da continuare'), findsNothing);
    expect(find.text('Da iniziare'), findsOneWidget);
    expect(find.text('Visti'), findsOneWidget);
    // Visti chiuso: Interstellar non c'è.
    expect(cardNames(tester), ['Parasite']);
    expect(api.itemQueries.single.favoritesOnly, isTrue);
    expect(api.itemQueries.single.includeSortFields, isTrue);
  });

  testWidgets('sulla TV la pagina si monta', (tester) async {
    await pumpList(
      tester,
      FakeLibraryApi()
        ..onItems = (query, start, limit) =>
            query.favoritesOnly ? pageOf(library()) : pageOf([]),
      size: const Size(960, 540),
      tv: true,
    );
    expect(find.text('LA MIA LISTA'), findsOneWidget);
    expect(find.text('Da iniziare'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Visti si apre e si chiude', (tester) async {
    await pumpList(tester, apiWith(library()));
    final header = find.ancestor(
      of: find.text('Visti'),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.expanded != null,
      ),
    );
    expect(tester.widget<Semantics>(header.first).properties.expanded, isFalse);

    await tester.tap(find.text('Visti'));
    await tester.pumpAndSettle();
    expect(cardNames(tester), ['Parasite', 'Interstellar']);
    expect(tester.widget<Semantics>(header.first).properties.expanded, isTrue);

    await tester.tap(find.text('Visti'));
    await tester.pumpAndSettle();
    expect(cardNames(tester), ['Parasite']);
  });

  testWidgets('scheda Serie dall\'indirizzo e dal cartellone', (tester) async {
    final router = await pumpList(
      tester,
      apiWith(library()),
      location: '/mylist?kind=series',
    );
    expect(
      find.text('1 serie: 1 da continuare.', findRichText: true),
      findsOneWidget,
    );
    expect(cardNames(tester), isEmpty);

    await tester.tap(find.byKey(const ValueKey('mylist-tab-movies')));
    await tester.pumpAndSettle();
    expect(location(router), '/mylist?kind=movies');
    expect(
      find.text('2 film: 1 da iniziare, 1 visto.', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('mylist-tab-all')));
    await tester.pumpAndSettle();
    expect(location(router), '/mylist');
  });

  testWidgets('ordina per titolo e verso', (tester) async {
    final api = apiWith([
      ...library(),
      testItem(
        id: 'a',
        name: 'Arrival',
        favorite: true,
        dateCreated: '2023-01-01T00:00:00Z',
      ),
      testItem(
        id: 'd',
        name: 'Dune',
        favorite: true,
        dateCreated: '2024-05-15T00:00:00Z',
      ),
    ]);
    await pumpList(tester, api);
    expect(cardNames(tester), ['Dune', 'Parasite', 'Arrival']);

    await tester.tap(find.text('Ordina: Aggiunti alla lista'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina: Titolo').last);
    await tester.pumpAndSettle();
    expect(cardNames(tester), ['Arrival', 'Dune', 'Parasite']);

    await tester.tap(find.byTooltip('Inverti l\'ordine'));
    await tester.pumpAndSettle();
    expect(cardNames(tester), ['Parasite', 'Dune', 'Arrival']);

    // Un'altra voce riparte dal verso di default.
    await tester.tap(find.text('Ordina: Titolo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina: Aggiunti alla lista').last);
    await tester.pumpAndSettle();
    expect(cardNames(tester), ['Dune', 'Parasite', 'Arrival']);
    // Si ordina nell'app: nessuna nuova richiesta.
    expect(api.itemQueries, hasLength(1));
  });

  testWidgets('oltre 24 titoli: generi e ricerca; con 24 no', (tester) async {
    await pumpList(tester, apiWith(many(25)));
    expect(find.byType(CatalogGenreIndex), findsOneWidget);
    expect(find.text('Cerca nella lista'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'film 0');
    await tester.pump();
    // Il punta (Film 24) resta nel cartellone; da 00 a 09 senza attesa.
    expect(cardNames(tester), hasLength(10));
  });

  testWidgets('con 24 titoli niente generi né ricerca', (tester) async {
    await pumpList(tester, apiWith(many(24)));
    expect(find.byType(CatalogGenreIndex), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('ricerca senza risultati: Azzera filtri', (tester) async {
    await pumpList(tester, apiWith(many(25)));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(
      find.text('Nessun titolo della lista con questi filtri.'),
      findsOneWidget,
    );
    expect(cardNames(tester), isEmpty);

    await tester.tap(find.text('Azzera filtri'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nessun titolo della lista con questi filtri.'),
      findsNothing,
    );
    expect(cardNames(tester), hasLength(24));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('cambiare scheda azzera il genere', (tester) async {
    await pumpList(tester, apiWith(many(25)));
    await tester.tap(find.text('Commedia'));
    await tester.pumpAndSettle();
    expect(cardNames(tester), hasLength(12));

    await tester.tap(find.byKey(const ValueKey('mylist-tab-movies')));
    await tester.pumpAndSettle();
    expect(cardNames(tester), hasLength(24));
  });

  testWidgets('lista vuota: testo e Vai ai film / Vai alle serie', (
    tester,
  ) async {
    final router = await pumpList(tester, apiWith([]));
    expect(
      find.text(
        'Qui trovi i film e le serie che salvi con il cuore, nella scheda '
        'del titolo o nell\'anteprima.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mylist-tab-all')), findsNothing);
    expect(find.text('Ordina: Aggiunti alla lista'), findsNothing);
    expect(find.text('Vai alle serie'), findsOneWidget);

    await tester.tap(find.text('Vai ai film'));
    await tester.pumpAndSettle();
    expect(location(router), '/movies');
  });

  testWidgets('scheda Film vuota: "Nessun film nella lista."', (tester) async {
    await pumpList(
      tester,
      apiWith([library().first]),
      location: '/mylist?kind=movies',
    );
    expect(
      find.text('Nessun film nella lista.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Vai ai film'), findsOneWidget);
    expect(find.text('Vai alle serie'), findsNothing);
    expect(find.byKey(const ValueKey('mylist-tab-series')), findsOneWidget);
  });

  testWidgets(
    'Da continuare di una serie: "S2:E3, 5 episodi da vedere", con Nuovo '
    'episodio; un film: "Riprendi da"',
    (tester) async {
      final now = DateTime.utc(2026, 11, 15, 12);
      await withClock(Clock.fixed(now), () async {
        final api =
            apiWith([
                // Iniziato più di recente: è il punta.
                testItem(
                  id: 'h',
                  name: 'Heat',
                  favorite: true,
                  positionTicks: 10 * _minute,
                  dateCreated: '2024-07-01T00:00:00Z',
                ),
                testItem(
                  id: 'vq',
                  name: 'VisionQuest',
                  kind: ItemKind.series,
                  favorite: true,
                  recursiveCount: 10,
                  unplayedCount: 5,
                  playedPercentage: 50,
                  dateCreated: '2024-06-01T00:00:00Z',
                  dateLastMediaAdded: now
                      .subtract(const Duration(days: 3))
                      .toIso8601String(),
                ),
                testItem(
                  id: 'al',
                  name: 'Alien',
                  favorite: true,
                  runtimeMinutes: 118,
                  positionTicks: 52 * _minute,
                  dateCreated: '2024-05-01T00:00:00Z',
                ),
              ])
              ..nextUpItems = [
                testItem(
                  id: 'e',
                  name: 'Episodio',
                  kind: ItemKind.episode,
                  seriesId: 'vq',
                  seasonIndex: 2,
                  index: 3,
                ),
              ];
        await pumpList(tester, api);
        expect(find.text('Da continuare'), findsOneWidget);
        expect(
          find.text('Nuovo episodio, S2:E3, 5 episodi da vedere'),
          findsOneWidget,
        );
        expect(find.text('Riprendi da 52 min, ne restano 66'), findsOneWidget);
        expect(api.nextUpLimits, [100]);
      });
    },
  );

  // Un cambio sul server (o una riconnessione) ricarica la lista: intanto
  // resta quella vecchia, senza scheletro.
  testWidgets('ricaricando dopo un cambio sul server resta la lista', (
    tester,
  ) async {
    final api = apiWith(library());
    await pumpList(tester, api);
    expect(cardNames(tester), ['Parasite']);

    final gate = api.favoritesGate = Completer<void>();
    ProviderScope.containerOf(
      tester.element(find.byType(MyListScreen)),
    ).read(libraryRevisionProvider.notifier).bump();
    await tester.pump();
    await tester.pump();
    // La nuova richiesta è partita e non è ancora tornata.
    expect(api.itemQueries, hasLength(2));
    expect(find.byType(PosterGridSkeleton), findsNothing);
    expect(cardNames(tester), ['Parasite']);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PosterGridSkeleton), findsNothing);
    expect(cardNames(tester), ['Parasite']);
  });

  testWidgets('le date di titoli non più nella lista si tolgono', (
    tester,
  ) async {
    final prefs = FakeDisplayPreferencesApi()
      ..myListAdded = {'p': DateTime.utc(2025), 'gone': DateTime.utc(2025)};
    final router = GoRouter(
      initialLocation: '/mylist',
      routes: [
        GoRoute(
          path: '/mylist',
          builder: (_, _) => const Scaffold(body: MyListScreen()),
        ),
      ],
    );
    await pumpAppRouter(
      tester,
      router,
      overrides: [
        libraryApiProvider.overrideWithValue(apiWith(library())),
        displayPreferencesApiProvider.overrideWithValue(prefs),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyListScreen)),
    );
    expect(container.read(myListAddedProvider).value!.keys, ['p']);
  });

  // Una scheda aperta sopra la pagina accende un cuore: la lista in memoria
  // non ha il titolo, ma la sua data non si perde.
  testWidgets('la data di un titolo aggiunto altrove resta e si salva', (
    tester,
  ) async {
    final prefs = FakeDisplayPreferencesApi();
    await pumpList(tester, apiWith(library()), prefs: prefs);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyListScreen)),
    );
    await container
        .read(userDataOverridesProvider.notifier)
        .toggleFavorite(testItem(id: 'new', name: 'Nuovo'));
    await tester.pumpAndSettle();
    expect(container.read(myListAddedProvider).value!.keys, contains('new'));
    expect(prefs.myListAddedWrites.last.keys, contains('new'));
  });

  testWidgets('punta senza fondale: il cartellone usa quello di un altro', (
    tester,
  ) async {
    await pumpList(
      tester,
      apiWith([
        JellyfinItem.fromJson({
          'Id': 'vq',
          'Name': 'VisionQuest',
          'Type': 'Series',
          'RecursiveItemCount': 10,
          'DateCreated': '2024-06-01T00:00:00Z',
          'UserData': {
            'IsFavorite': true,
            'UnplayedItemCount': 5,
            'PlayedPercentage': 50,
          },
        }),
        ...library().skip(1),
      ]),
    );
    expect(tester.widget<CatalogBand>(find.byType(CatalogBand)).hero?.id, 'p');
  });

  // Griglia senza chiavi: togliendo Heat, la card di Arrival ne riusa
  // l'host. L'anteprima di Heat non deve restare aperta su Arrival.
  testWidgets('tolto dalla lista dall\'anteprima: l\'anteprima si chiude', (
    tester,
  ) async {
    final api = apiWith([
      testItem(
        id: 'd',
        name: 'Dune',
        favorite: true,
        dateCreated: '2024-05-01T00:00:00Z',
      ),
      testItem(
        id: 'h',
        name: 'Heat',
        favorite: true,
        dateCreated: '2024-04-01T00:00:00Z',
      ),
      testItem(
        id: 'a',
        name: 'Arrival',
        favorite: true,
        dateCreated: '2024-03-01T00:00:00Z',
      ),
    ]);
    await pumpList(tester, api);
    expect(cardNames(tester), ['Heat', 'Arrival']);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Heat')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsOneWidget);

    await tester.tap(find.byTooltip('Rimuovi da La mia lista'));
    await tester.pumpAndSettle();
    expect(api.favoriteCalls, [('h', false)]);
    expect(cardNames(tester), ['Arrival']);
    expect(find.byType(CardPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
