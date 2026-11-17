import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/search/search_screen.dart';
import 'package:wonderflix/ui/poster_card.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late SharedPreferences prefs;
  late FakeLibraryApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'search.recent.${testUser.id}': ['chernobyl', 'dune'],
    });
    prefs = await SharedPreferences.getInstance();
    api = FakeLibraryApi()
      ..filtersByKind[ItemKind.movie] =
          const LibraryFilters(genres: ['Dramma', 'Fantascienza'])
      ..filtersByKind[ItemKind.series] =
          const LibraryFilters(genres: ['Dramma'])
      ..onItems = ((query, start, limit) {
        if (query.sort != CatalogSort.dateAdded) return pageOf([]);
        return query.kinds.contains(ItemKind.movie)
            ? pageOf([testItem(id: 'hope', name: 'Hope')])
            : pageOf([
                testItem(id: 'sg', name: 'Steins;Gate', kind: ItemKind.series),
              ]);
      });
  });

  List<Override> overrides() => [
        libraryApiProvider.overrideWithValue(api),
        requestsAvailableProvider.overrideWithValue(false),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ];

  Future<void> pumpSearch(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides());
    await tester.pump();
  }

  testWidgets('prima di scrivere: recenti, generi e aggiunti di recente',
      (tester) async {
    await pumpSearch(tester);

    expect(find.text('Titolo, attore o regista'), findsOneWidget);
    expect(find.text('Ricerche recenti'), findsOneWidget);
    expect(find.text('Solo su questo dispositivo'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'chernobyl'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'dune'), findsOneWidget);
    expect(find.text('Prova con un genere'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Dramma'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Fantascienza'), findsOneWidget);
    expect(find.text('Aggiunti di recente'), findsOneWidget);
    expect(find.text('Hope'), findsOneWidget);
    expect(find.text('Steins;Gate'), findsOneWidget);
    // Il primo è un film.
    expect(tester.getTopLeft(find.text('Hope')).dx,
        lessThan(tester.getTopLeft(find.text('Steins;Gate')).dx));
  });

  testWidgets('senza recenti né aggiunti: solo i generi', (tester) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api.onItems = (query, start, limit) => pageOf([]);
    await pumpSearch(tester);

    expect(find.text('Ricerche recenti'), findsNothing);
    expect(find.text('Aggiunti di recente'), findsNothing);
    expect(find.text('Prova con un genere'), findsOneWidget);
  });

  testWidgets('un recente si cerca, la ✕ lo toglie, Cancella li toglie tutti',
      (tester) async {
    await pumpSearch(tester);

    await tester.tap(find.widgetWithText(InputChip, 'dune'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Ricerche recenti'), findsNothing);
    expect(api.peopleCalls.map((c) => c.$1), ['dune']);

    // Di nuovo vuoto: la pagina prima di scrivere torna.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.byTooltip('Togli “chernobyl”'));
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'chernobyl'), findsNothing);
    expect(prefs.getStringList('search.recent.${testUser.id}'), ['dune']);

    await tester.tap(find.text('Cancella'));
    await tester.pump();
    expect(find.text('Ricerche recenti'), findsNothing);
    expect(prefs.getStringList('search.recent.${testUser.id}'), isEmpty);
  });

  testWidgets('svuotare il campo non rilegge generi e aggiunti e tiene Serie',
      (tester) async {
    await pumpSearch(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Serie'));
    await tester.pump();
    await tester.pump();
    int latestCalls() => api.itemQueries
        .where((q) => q.sort == CatalogSort.dateAdded)
        .length;
    final filters = api.filtersCalls.length;
    final latest = latestCalls();

    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Prova con un genere'), findsNothing);
    await tester.tap(find.byTooltip('Svuota'));
    await tester.pump();

    expect(find.text('Aggiunti di recente'), findsOneWidget);
    expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Serie'))
            .selected,
        isTrue);
    expect(api.filtersCalls.length, filters);
    expect(latestCalls(), latest);
  });

  testWidgets('generi delle serie in errore: restano Film e Serie',
      (tester) async {
    api.filtersErrors[ItemKind.series] = Exception('giù');
    await pumpSearch(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Serie'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Prova con un genere'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Film'));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(ActionChip, 'Dramma'), findsOneWidget);
  });

  testWidgets('aggiunti di recente: una fila intera sopra lo schermo del '
      'telefono', (tester) async {
    api.onItems = (query, start, limit) => query.sort == CatalogSort.dateAdded &&
            query.kinds.contains(ItemKind.movie)
        ? pageOf([for (var i = 0; i < 8; i++) testItem(id: 'm$i', name: 'M$i')])
        : pageOf([]);
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(), surfaceSize: const Size(900, 1000));
    await tester.pump();
    // 868 px di griglia: cinque colonne del catalogo.
    expect(find.byType(PosterCard), findsNWidgets(5));
  });

  testWidgets('Serie e poi un genere aprono il catalogo Serie col genere',
      (tester) async {
    final router = GoRouter(initialLocation: '/search', routes: [
      GoRoute(
          path: '/search',
          builder: (_, _) => const Scaffold(body: SearchScreen())),
      GoRoute(path: '/:p', builder: (_, _) => const SizedBox()),
    ]);
    await pumpAppRouter(tester, router, overrides: overrides());
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Serie'));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(ActionChip, 'Fantascienza'), findsNothing);
    await tester.tap(find.widgetWithText(ActionChip, 'Dramma'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.toString(),
        '/series?genre=Dramma');
  });

  testWidgets('"Vedi tutti" degli aggiunti apre il catalogo del tipo scelto, '
      'Indietro torna a Cerca', (tester) async {
    final router = GoRouter(initialLocation: '/search', routes: [
      GoRoute(
          path: '/search',
          builder: (_, _) => const Scaffold(body: SearchScreen())),
      GoRoute(path: '/:p', builder: (_, _) => const SizedBox()),
    ]);
    await pumpAppRouter(tester, router, overrides: overrides());
    await tester.pump();
    String location() => router.state.uri.toString();

    await tester.tap(find.widgetWithText(TextButton, 'Vedi tutti'));
    await tester.pumpAndSettle();
    expect(location(), '/movies');

    router.pop();
    await tester.pumpAndSettle();
    expect(location(), '/search');
    expect(find.byType(SearchScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Serie'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Vedi tutti'));
    await tester.pumpAndSettle();
    expect(location(), '/series');
  });
}
