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
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/person/person_screen.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
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
