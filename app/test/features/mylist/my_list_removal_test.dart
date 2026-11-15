import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';
import 'package:wonderflix/ui/poster_card.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  final d0 = DateTime.utc(2025, 3, 1, 12);

  /// VisionQuest serie iniziata (punta), Ronin film iniziato, Parasite film
  /// nuovo, Interstellar e Heat visti, Severance serie in corso vista tutta.
  List<JellyfinItem> library({bool parasite = true}) => [
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
      id: 'r',
      name: 'Ronin',
      favorite: true,
      positionTicks: 10 * 600000000,
      dateCreated: '2024-05-15T00:00:00Z',
    ),
    if (parasite)
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
    testItem(
      id: 'h',
      name: 'Heat',
      favorite: true,
      played: true,
      dateCreated: '2024-03-01T00:00:00Z',
    ),
    testItem(
      id: 's',
      name: 'Severance',
      kind: ItemKind.series,
      favorite: true,
      played: true,
      status: 'Continuing',
      recursiveCount: 10,
      unplayedCount: 0,
      dateCreated: '2024-02-01T00:00:00Z',
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

  Future<void> pumpList(
    WidgetTester tester,
    FakeLibraryApi api, {
    bool tv = false,
    bool touch = false,
    FakeDisplayPreferencesApi? prefs,
  }) async {
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
      surfaceSize: const Size(1440, 2400),
      tv: tv,
      touch: touch,
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
  }

  TestGesture? mouse;
  setUp(() => mouse = null);

  Future<void> hover(WidgetTester tester, Finder target) async {
    if (mouse == null) {
      final gesture = mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
    }
    await mouse!.moveTo(tester.getCenter(target));
    await tester.pump();
  }

  Future<void> openWatched(WidgetTester tester) async {
    await tester.tap(find.text('Visti'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cuore al passaggio del mouse: toglie, avviso, Annulla rimette con la '
    'data di prima',
    (tester) async {
      final prefs = FakeDisplayPreferencesApi()..myListAdded = {'p': d0};
      final api = apiWith(library());
      await pumpList(tester, api, prefs: prefs);
      expect(find.byTooltip('Togli dalla lista'), findsNothing);

      await hover(tester, find.text('Parasite'));
      await tester.tap(find.byTooltip('Togli dalla lista'));
      await tester.pumpAndSettle();
      expect(api.favoriteCalls, [('p', false)]);
      expect(find.text('Tolto dalla lista: Parasite'), findsOneWidget);
      expect(cardNames(tester), isNot(contains('Parasite')));
      expect(prefs.myListAddedWrites.last.keys, isNot(contains('p')));

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(api.favoriteCalls.last, ('p', true));
      expect(cardNames(tester), contains('Parasite'));
      expect(prefs.myListAddedWrites.last['p'], d0);
    },
  );

  // Review Focus 1: la lista ricaricata non ha più il titolo, l'override da
  // solo non basta.
  testWidgets('Annulla dopo una ricarica: il titolo torna nella pagina', (
    tester,
  ) async {
    var serverHasParasite = true;
    final api = FakeLibraryApi()
      ..onItems = (query, start, limit) => query.favoritesOnly
          ? pageOf(library(parasite: serverHasParasite))
          : pageOf([]);
    await pumpList(tester, api);

    await hover(tester, find.text('Parasite'));
    await tester.tap(find.byTooltip('Togli dalla lista'));
    await tester.pumpAndSettle();
    serverHasParasite = false;
    ProviderScope.containerOf(
      tester.element(find.byType(MyListScreen)),
    ).read(libraryRevisionProvider.notifier).bump();
    await tester.pumpAndSettle();
    expect(cardNames(tester), isNot(contains('Parasite')));

    serverHasParasite = true;
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(cardNames(tester), contains('Parasite'));
  });

  testWidgets('l\'avviso sparisce dopo 5 secondi', (tester) async {
    await pumpList(tester, apiWith(library()));
    await hover(tester, find.text('Parasite'));
    await tester.tap(find.byTooltip('Togli dalla lista'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 4500));
    expect(find.text('Tolto dalla lista: Parasite'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Tolto dalla lista: Parasite'), findsNothing);
  });

  testWidgets('la card larga ha anche il play, le locandine no', (
    tester,
  ) async {
    await pumpList(tester, apiWith(library()));
    await hover(tester, find.text('Ronin'));
    expect(find.byTooltip('Togli dalla lista'), findsOneWidget);
    expect(find.byTooltip('Riprendi'), findsOneWidget);
  });

  for (final (name, touch, tv) in [
    ('touch', true, false),
    ('TV', false, true),
  ]) {
    testWidgets('su $name la card non ha il cuore', (tester) async {
      await pumpList(tester, apiWith(library()), touch: touch, tv: tv);
      await hover(tester, find.text('Parasite'));
      expect(find.byTooltip('Togli dalla lista'), findsNothing);
      await hover(tester, find.text('Ronin'));
      expect(find.byTooltip('Togli dalla lista'), findsNothing);
    });
  }

  testWidgets(
    'Togli i visti: tutti tranne la serie in corso, un avviso col numero',
    (tester) async {
      final api = apiWith(library());
      await pumpList(tester, api);
      await tester.tap(find.text('Togli i visti dalla lista'));
      await tester.pumpAndSettle();
      expect(api.favoriteCalls, unorderedEquals([('i', false), ('h', false)]));
      expect(find.text('Tolti dalla lista 2 titoli visti'), findsOneWidget);
      await openWatched(tester);
      expect(cardNames(tester), contains('Severance'));
      expect(cardNames(tester), isNot(contains('Heat')));
    },
  );

  // Review Focus 5.
  testWidgets('solo serie in corso viste tutte: il gruppo c\'è, il pulsante '
      'no', (tester) async {
    await pumpList(
      tester,
      apiWith([
        for (final i in library())
          if (i.id != 'i' && i.id != 'h') i,
      ]),
    );
    expect(find.text('Visti'), findsOneWidget);
    expect(find.text('Togli i visti dalla lista'), findsNothing);
  });

  testWidgets('un titolo che non si toglie torna e l\'avviso lo dice', (
    tester,
  ) async {
    final api = apiWith(library())..favoriteErrors['h'] = Exception('no');
    await pumpList(tester, api);
    await tester.tap(find.text('Togli i visti dalla lista'));
    await tester.pumpAndSettle();
    expect(find.text('Non sono riuscito a togliere 1 titolo'), findsOneWidget);
    expect(find.text('Tolti dalla lista 2 titoli visti'), findsNothing);
    await openWatched(tester);
    expect(cardNames(tester), contains('Heat'));
    expect(cardNames(tester), isNot(contains('Interstellar')));
  });

  testWidgets('in TV Togli i visti chiede conferma, focus su Annulla', (
    tester,
  ) async {
    final api = apiWith(library());
    await pumpList(tester, api, tv: true);
    Focus.of(
      tester.element(find.text('Togli i visti dalla lista')),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Togliere 2 titoli visti dalla lista?'), findsOneWidget);
    expect(
      Focus.of(
        tester.element(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Annulla'),
          ),
        ),
      ).hasPrimaryFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.favoriteCalls, isEmpty);
  });

  testWidgets('in TV con Togli toglie i visti', (tester) async {
    final api = apiWith(library());
    await pumpList(tester, api, tv: true);
    Focus.of(
      tester.element(find.text('Togli i visti dalla lista')),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Togli'));
    await tester.pumpAndSettle();
    expect(api.favoriteCalls, unorderedEquals([('i', false), ('h', false)]));
  });
}
