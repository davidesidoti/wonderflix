import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/page_transitions.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/detail/movie_detail_view.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/person/person_screen.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/card_preview_host.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

/// Voli Hero con un vero `GoRouter`: scheda e persona come in `router.dart`
/// (`detailPage`, `HeroLaunch` da `extra`), animazioni complete.
void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['m1'] = testItem(
        id: 'm1',
        name: 'Dune: Parte Due',
        people: [
          {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
        ],
      )
      ..itemsById['m2'] = testItem(
        id: 'm2',
        name: 'Arrival',
        people: [
          {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Louise', 'Type': 'Actor'},
        ],
      )
      ..itemsById['p9'] = testItem(
          id: 'p9', name: 'Zendaya', kind: ItemKind.person, year: null)
      // "Simili" è la stessa lista per ogni scheda.
      ..similarItems = [
        testItem(id: 'm1', name: 'Dune: Parte Due'),
        testItem(id: 'm2', name: 'Arrival'),
      ]
      ..onItems = (query, start, limit) => query.personId == 'p9'
          ? pageOf([testItem(id: 'm1', name: 'Dune: Parte Due')])
          : pageOf([]);
  });

  HeroLaunch? launchOf(GoRouterState state) =>
      state.extra is HeroLaunch ? state.extra as HeroLaunch : null;

  Future<GoRouter> pumpRouter(WidgetTester tester, String initial) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        ShellRoute(
          // Shell minima: lo Scaffold che in app dà l'AppShell.
          builder: (context, state, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/item/:id',
              pageBuilder: (context, state) => detailPage(
                context,
                state,
                ItemDetailScreen(
                  key: ValueKey(state.uri.toString()),
                  itemId: state.pathParameters['id']!,
                  launch: launchOf(state),
                ),
                underBar: false,
              ),
            ),
            GoRoute(
              path: '/person/:id',
              pageBuilder: (context, state) => detailPage(
                context,
                state,
                PersonScreen(
                  key: ValueKey(state.pathParameters['id']),
                  personId: state.pathParameters['id']!,
                  launch: launchOf(state),
                ),
                underBar: true,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider.overrideWithValue(
            (image, fit) => const ColoredBox(color: Color(0xFF333333))),
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => WfMotionScope(
            motion: const WfMotion(MotionLevel.full), child: child!),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  /// Clic sulla card o sul volto con [text] della pagina in cima.
  Future<void> open(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Tag degli `Hero` di ogni pagina della pila, dalla più bassa.
  List<Set<Object>> heroTagsByPage(WidgetTester tester) {
    final byRoute = <Route<dynamic>, Set<Object>>{};
    for (final element in find.byType(Hero, skipOffstage: false).evaluate()) {
      final route = ModalRoute.of(element)!;
      byRoute.putIfAbsent(route, () => {}).add((element.widget as Hero).tag);
    }
    final pages = byRoute.keys.first.navigator!.widget.pages;
    return [
      for (final page in pages)
        byRoute.entries
                .where((e) => identical(e.key.settings, page))
                .firstOrNull
                ?.value ??
            const {},
    ];
  }

  /// Tra le due pagine in cima vola solo l'immagine del lancio.
  void expectOnlyLaunchShared(WidgetTester tester, GoRouter router) {
    final launch = launchOf(router.state);
    expect(launch, isNotNull);
    final pages = heroTagsByPage(tester);
    expect(pages.length, greaterThanOrEqualTo(3));
    final top = pages.last;
    final below = pages[pages.length - 2];
    expect(top.length, greaterThan(1), reason: 'la pagina ha le sue card');
    expect(below.length, greaterThan(1));
    expect(top.intersection(below), {launch!.tag});
  }

  testWidgets('volo reale nella ShellRoute: andata e ritorno senza errori',
      (tester) async {
    final router = await pumpRouter(tester, '/item/m1');
    final card = find.text('Arrival');
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(wfHeroFlightKey), findsOneWidget, reason: 'in volo');
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/m2');
    expect(find.byKey(wfHeroFlightKey), findsNothing);

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(wfHeroFlightKey), findsOneWidget,
        reason: "l'immagine torna nella card");
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/m1');
    expect(find.byKey(wfHeroFlightKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Dettagli" nell\'anteprima: il volo parte dallo sfondo',
      (tester) async {
    final router = await pumpRouter(tester, '/item/m1');
    final card = find.widgetWithText(PosterCard, 'Arrival');
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(card));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsOneWidget);

    await tester.tap(find.byTooltip('Dettagli'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(wfHeroFlightKey), findsOneWidget,
        reason: "in volo dall'anteprima");
    // L'anteprima resta finché la pagina nuova è entrata, trasparente.
    expect(find.byType(CardPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/m2');
    expect(find.byType(CardPreview), findsNothing);
    expect(find.byKey(wfHeroFlightKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  /// Mouse fermo sulla card di [title] della pagina in cima finché si apre
  /// la sua anteprima.
  Future<TestGesture> openPreview(WidgetTester tester, String title) async {
    final card = find.widgetWithText(PosterCard, title);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(card));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsOneWidget);
    return mouse;
  }

  // La pagina della card smette di essere in cima mentre l'albero si
  // costruisce: l'anteprima si chiude al fotogramma dopo, senza errori.
  testWidgets('anteprima aperta, poi push: si chiude senza errori',
      (tester) async {
    final router = await pumpRouter(tester, '/item/m1');
    await openPreview(tester, 'Arrival');

    unawaited(router.push('/item/m2'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/m2');
    expect(tester.takeException(), isNull);
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('anteprima aperta su una pagina spinta, poi pop: senza errori',
      (tester) async {
    final router = await pumpRouter(tester, '/item/m1');
    unawaited(router.push('/item/m2'));
    await tester.pumpAndSettle();
    await openPreview(tester, 'Dune: Parte Due');

    router.pop();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/m1');
    expect(tester.takeException(), isNull);
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('"Dettagli", poi subito pop: l\'anteprima si chiude senza errori',
      (tester) async {
    final router = await pumpRouter(tester, '/item/m1');
    final mouse = await openPreview(tester, 'Arrival');

    await tester.tap(find.byTooltip('Dettagli'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // Al ritorno la card non è sotto il mouse: non riapre l'anteprima.
    await mouse.moveTo(Offset.zero);
    router.pop();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/m1');
    expect(tester.takeException(), isNull);
    expect(find.byType(CardPreview), findsNothing);
  });

  // I tooltip dei pulsanti dell'anteprima usano un overlay sopra di lei, non
  // quello del navigatore della shell (più in basso nell'albero dei render).
  testWidgets('tooltip dei pulsanti dell\'anteprima: sopra, senza errori',
      (tester) async {
    await pumpRouter(tester, '/item/m1');
    final mouse = await openPreview(tester, 'Arrival');

    await mouse.moveTo(tester.getCenter(find.byTooltip('Riproduci')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    final tip = find.descendant(
        of: find.byTooltip('Riproduci'), matching: find.text('Riproduci'));
    expect(tip, findsOneWidget);
    // Nell'overlay dell'anteprima, sopra di lei; non in quello della shell.
    expect(
        find.descendant(
            of: find.byType(CardPreviewHost),
            matching: find.descendant(
                of: find.byType(Overlay), matching: tip)),
        findsOneWidget);
    expect(find.byType(CardPreview), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // Scheda scorsa: lo sfondo è traslato, ingrandito, scurito e ritagliato,
  // il volo di ritorno partirebbe da un rettangolo sbagliato. Torna
  // indietro con la sola transizione della pagina.
  for (final scrolled in [false, true]) {
    testWidgets(
        scrolled
            ? 'ritorno da una scheda scorsa: nessun volo'
            : 'ritorno da una scheda in cima: volo', (tester) async {
      final router = await pumpRouter(tester, '/item/m1');
      await open(tester, find.text('Arrival'));
      expect(router.state.uri.path, '/item/m2');
      if (scrolled) {
        final controller = tester
            .widget<MovieDetailView>(find.byType(MovieDetailView))
            .controller!;
        expect(controller.position.maxScrollExtent, greaterThan(300));
        controller.jumpTo(300);
        await tester.pumpAndSettle();
      }

      router.pop();
      // Il volo parte dopo il primo fotogramma del ritorno.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(wfHeroFlightKey),
          scrolled ? findsNothing : findsOneWidget);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/item/m1');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A → Simili B → Simili A′: nessun volo oltre al lancio',
      (tester) async {
    final router = await pumpRouter(tester, '/item/m1');
    await open(tester, find.text('Arrival'));
    expect(router.state.uri.path, '/item/m2');
    await open(tester, find.text('Dune: Parte Due'));
    expect(router.state.uri.path, '/item/m1');
    expectOnlyLaunchShared(tester, router);
  });

  testWidgets('A → cast P → filmografia A′: nessun volo oltre al lancio',
      (tester) async {
    final router = await pumpRouter(tester, '/item/m1');
    await open(tester, find.text('Zendaya'));
    expect(router.state.uri.path, '/person/p9');
    await open(tester, find.text('Dune: Parte Due'));
    expect(router.state.uri.path, '/item/m1');
    expectOnlyLaunchShared(tester, router);
  });
}
