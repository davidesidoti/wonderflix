import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_band.dart';
import 'package:wonderflix/features/catalog/catalog_genre_index.dart';
import 'package:wonderflix/features/catalog/catalog_screen.dart';
import 'package:wonderflix/features/detail/detail_providers.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_band.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';
import 'package:wonderflix/features/mylist/my_list_tools.dart';
import 'package:wonderflix/features/mylist/my_list_view.dart';
import 'package:wonderflix/ui/landscape_card.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

const _minute = 600000000;

void main() {
  /// VisionQuest iniziata (il punta), [resume] film iniziati, [start] film
  /// nuovi e [watched] visti.
  List<JellyfinItem> library({
    bool hero = true,
    int resume = 0,
    int start = 12,
    int watched = 2,
  }) => [
    if (hero)
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
    for (var i = 0; i < resume; i++)
      testItem(
        id: 'r$i',
        name: 'Iniziato $i',
        favorite: true,
        runtimeMinutes: 100,
        positionTicks: 10 * _minute,
        dateCreated: '2024-05-0${i + 1}T00:00:00Z',
      ),
    for (var i = 0; i < start; i++)
      testItem(
        id: 's$i',
        name: 'Nuovo $i',
        favorite: true,
        genres: const ['Dramma'],
        dateCreated: DateTime.utc(
          2024,
          3,
          1,
        ).add(Duration(days: i)).toIso8601String(),
      ),
    for (var i = 0; i < watched; i++)
      testItem(
        id: 'w$i',
        name: 'Visto $i',
        favorite: true,
        played: true,
        dateCreated: '2024-01-0${i + 1}T00:00:00Z',
      ),
  ];

  Future<void> pumpList(
    WidgetTester tester,
    List<JellyfinItem> items, {
    bool tv = true,
    Size size = const Size(960, 540),
    String location = '/mylist',
  }) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/mylist',
          builder: (context, state) => Scaffold(
            body: MyListScreen(
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
        libraryApiProvider.overrideWithValue(
          FakeLibraryApi()
            ..onItems = (query, start, limit) =>
                query.favoritesOnly ? pageOf(items) : pageOf([]),
        ),
        displayPreferencesApiProvider.overrideWithValue(
          FakeDisplayPreferencesApi(),
        ),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
        // VisionQuest riparte da S1:E8, già iniziato.
        seriesNextEpisodeProvider.overrideWith(
          (ref, id) => testItem(
            id: 'e8',
            name: 'Otto',
            kind: ItemKind.episode,
            seriesId: 'vq',
            seasonIndex: 1,
            index: 8,
            positionTicks: 5 * _minute,
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// L'elemento col focus.
  Finder focused() => find.byElementPredicate(
    (e) => e == FocusManager.instance.primaryFocus?.context,
  );

  /// I testi sotto il focus, in fila.
  String focusedLabel(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(of: focused(), matching: find.byType(Text)),
    ))
      t.data ?? t.textSpan?.toPlainText() ?? '',
  ].join(' ');

  bool focusedIn(Finder of) =>
      find.ancestor(of: focused(), matching: of).evaluate().isNotEmpty;

  double scrollOffset(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!
      .offset;

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('TV: il focus parte da Riprendi S1:E8', (tester) async {
    await pumpList(tester, library());
    expect(focusedLabel(tester), 'Riprendi S1:E8');
  });

  testWidgets('TV: su va alle schede, giù agli attrezzi e poi a Da iniziare', (
    tester,
  ) async {
    await pumpList(tester, library());
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedIn(find.byType(CatalogBandTab)), isTrue);

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedLabel(tester), 'Riprendi S1:E8');

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(find.byType(MyListTools)), isTrue);

    await key(tester, LogicalKeyboardKey.arrowDown);
    final card = find.ancestor(
      of: focused(),
      matching: find.byType(PosterCard),
    );
    // Una card della prima fila di Da iniziare.
    expect(tester.widget<PosterCard>(card).item.name, startsWith('Nuovo'));
    expect(
      tester.getTopLeft(card).dy,
      tester.getTopLeft(find.byType(PosterCard).first).dy,
    );
  });

  testWidgets('TV: col focus nei gruppi il cartellone esce dallo schermo', (
    tester,
  ) async {
    await pumpList(tester, library());
    expect(scrollOffset(tester), 0);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn(find.byType(PosterCard)), isTrue);
    expect(scrollOffset(tester), greaterThanOrEqualTo(160));
    expect(find.byType(CatalogBand).hitTestable(), findsNothing);

    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedIn(find.byType(MyListTools)), isTrue);
    expect(scrollOffset(tester), 0);
  });

  testWidgets('TV: Da continuare è una fila che non va a capo', (tester) async {
    await pumpList(tester, library(resume: 5));
    final cards = find.byType(LandscapeCard);
    expect(cards, findsNWidgets(5));
    final tops = {
      for (final e in cards.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(tops, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV: Visti ha la testata e "Togli i visti"', (tester) async {
    await pumpList(tester, library(start: 1));
    // Giù: attrezzi, Da iniziare, la testata di Visti.
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focusedLabel(tester), contains('Visti'));
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedLabel(tester), 'Togli i visti dalla lista');
  });

  testWidgets('TV: niente generi né ricerca con 30 titoli', (tester) async {
    await pumpList(tester, library(start: 30));
    expect(find.byType(CatalogGenreIndex), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('TV, tutti visti: focus sul primo attrezzo', (tester) async {
    await pumpList(tester, library(hero: false, start: 0, watched: 3));
    expect(focusedIn(find.byType(MyListTools)), isTrue);
  });

  testWidgets('TV, lista vuota: focus su Vai ai film', (tester) async {
    await pumpList(tester, []);
    expect(focusedLabel(tester), 'Vai ai film');
  });

  testWidgets('TV: schede sopra il titolo, pulsante e frase in una riga', (
    tester,
  ) async {
    await pumpList(tester, library());
    final title = tester.getRect(find.text('LA MIA LISTA'));
    expect(
      tester.getRect(find.byType(CatalogBandTab).first).bottom,
      lessThanOrEqualTo(title.top),
    );
    final action = find.byType(MyListBandAction);
    expect(
      tester.getRect(action).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(MyListTools)).top),
    );
    final button = tester.getRect(
      find.descendant(of: action, matching: find.byType(WfButton)),
    );
    final phrase = tester.getRect(
      find.descendant(
        of: action,
        matching: find.textContaining('VisionQuest', findRichText: true),
      ),
    );
    expect(phrase.left, greaterThan(button.right));
    // La prima fila di Da iniziare si vede già sui 540 px della TV.
    expect(tester.getRect(find.byType(PosterCard).first).top, lessThan(540));
  });

  testWidgets('TV, scheda vuota: le schede sopra il titolo', (tester) async {
    await pumpList(tester, [
      testItem(id: 'p', name: 'Parasite', favorite: true),
    ], location: '/mylist?kind=series');
    expect(find.text('Vai alle serie'), findsOneWidget);
    expect(
      tester.getRect(find.byType(CatalogBandTab).first).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('LA MIA LISTA')).top),
    );
  });
}
