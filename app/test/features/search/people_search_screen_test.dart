import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/search/people_search_screen.dart';
import 'package:wonderflix/features/search/search_screen.dart';
import 'package:wonderflix/features/search/search_best.dart';
import 'package:wonderflix/ui/tv_focusable.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  List<JellyfinItem> people(int n) => [
        for (var i = 0; i < n; i++)
          testItem(id: 'p$i', name: 'Ist Persona $i', kind: ItemKind.person),
      ];

  List<Override> overrides(FakeLibraryApi api) => [
        libraryApiProvider.overrideWithValue(api),
        requestsAvailableProvider.overrideWithValue(false),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        sharedPreferencesProvider.overrideWithValue(prefs),
        clientInfoProvider.overrideWithValue(testClientInfo),
      ];

  testWidgets('tutte le persone di "ist", 100 per volta', (tester) async {
    final api = FakeLibraryApi()..people = people(150);
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: 'ist')),
        overrides: overrides(api));
    await tester.pump();
    await tester.pump();

    expect(find.text('Persone'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(api.peopleCalls, [('ist', 0, 100)]);
    expect(find.byType(SearchPersonTile), findsWidgets);

    // Scorre in fondo: arriva la seconda pagina.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pump();
    await tester.pump();
    expect(api.peopleCalls.last, ('ist', 100, 100));
    expect(api.peopleCalls.length, 2);

    // Tutte e 150 sono caricate: niente terza chiamata.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pump();
    await tester.pump();
    expect(api.peopleCalls.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la pagina nuova non sposta le persone già in vista',
      (tester) async {
    final api = FakeLibraryApi()
      ..people = people(150)
      ..delay = const Duration(milliseconds: 50);
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: 'ist')),
        overrides: overrides(api));
    await tester.pump(const Duration(milliseconds: 100));

    // jumpTo e non drag: il drag lascia uno scorrimento d'inerzia.
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pump();
    expect(api.peopleCalls.length, 2); // la seconda pagina è in arrivo
    final anchor = find.byKey(const ValueKey('person-p95'));
    final before = tester.getTopLeft(anchor);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SearchPersonTile), findsWidgets);
    expect(tester.getTopLeft(anchor), before);
  });

  testWidgets('uscendo mentre carica la risposta tardiva non fa niente',
      (tester) async {
    final api = FakeLibraryApi()
      ..people = people(150)
      ..delay = const Duration(milliseconds: 50);
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: 'ist')),
        overrides: overrides(api));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un errore mostra "Riprova", che ricarica la stessa pagina',
      (tester) async {
    final api = FakeLibraryApi()
      ..people = people(30)
      ..error = Exception('giù');
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: 'ist')),
        overrides: overrides(api));
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprova'), findsOneWidget);

    api.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprova'), findsNothing);
    expect(find.byType(SearchPersonTile), findsWidgets);
    expect(api.peopleCalls.last, ('ist', 0, 100));
  });

  testWidgets('errore alla pagina 2: restano le prime 100, Riprova riparte '
      'da 100', (tester) async {
    final api = FakeLibraryApi()..people = people(150);
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: 'ist')),
        overrides: overrides(api));
    await tester.pump();
    await tester.pump();

    api.error = Exception('giù');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // finisce l'inerzia
    expect(find.text('Riprova'), findsOneWidget);
    expect(find.byType(SearchPersonTile), findsWidgets);
    expect(api.peopleCalls.last, ('ist', 100, 100));

    api.error = null;
    final scroll =
        tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprova'), findsNothing);
    expect(api.peopleCalls.last, ('ist', 100, 100));
    expect(api.peopleCalls.length, 3);
    // Le prime 100 non sono ripartite da capo.
    expect(api.peopleCalls.where((c) => c.$2 == 0).length, 1);
  });

  testWidgets("una pagina vuota chiude l'elenco: niente altre chiamate",
      (tester) async {
    final api = FakeLibraryApi()
      ..people = people(100)
      ..peopleTotal = 150;
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: 'ist')),
        overrides: overrides(api));
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
      await tester.pump();
      await tester.pump();
    }
    expect(api.peopleCalls, [('ist', 0, 100), ('ist', 100, 100)]);
  });

  testWidgets('senza termine (/people senza q) non chiede le persone',
      (tester) async {
    final api = FakeLibraryApi()..people = people(150);
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: '')),
        overrides: overrides(api));
    await tester.pump();
    await tester.pump();
    expect(api.peopleCalls, isEmpty);
    expect(find.byType(SearchPersonTile), findsNothing);
    expect(find.text('Persone'), findsOneWidget);
  });

  testWidgets('TV: il focus parte dalla prima persona', (tester) async {
    final api = FakeLibraryApi()..people = people(5);
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: 'ist')),
        tv: true,
        surfaceSize: const Size(960, 540),
        overrides: overrides(api));
    await tester.pump();
    await tester.pump();

    final first = find.descendant(
        of: find.byKey(const ValueKey('person-p0')),
        matching: find.byType(TvFocusable));
    expect(Focus.of(tester.element(find.text('Ist Persona 0'))).hasFocus,
        isTrue);
    expect(first, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nessuna persona: una riga semplice', (tester) async {
    final api = FakeLibraryApi()..people = [];
    await pumpApp(
        tester,
        const Scaffold(body: PeopleSearchScreen(term: 'zzz')),
        overrides: overrides(api));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nessuna persona con questo nome'), findsOneWidget);
    expect(find.byType(SearchPersonTile), findsNothing);
  });

  group('da Cerca', () {
    late GoRouter router;

    setUp(() {
      router = GoRouter(initialLocation: '/search', routes: [
        GoRoute(
            path: '/search',
            builder: (_, _) => const Scaffold(body: SearchScreen())),
        GoRoute(
            path: '/people',
            builder: (_, state) => Scaffold(
                body: PeopleSearchScreen(
                    term: state.uri.queryParameters['q'] ?? ''))),
        GoRoute(path: '/person/:id', builder: (_, _) => const SizedBox()),
      ]);
    });

    FakeLibraryApi library() => FakeLibraryApi()
      ..people = people(12)
      ..peopleTotal = 150;

    Future<void> pumpSearch(WidgetTester tester,
        {Size size = const Size(1280, 800), bool touch = false}) async {
      await pumpAppRouter(tester, router,
          surfaceSize: size, touch: touch, overrides: overrides(library()));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ist');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    testWidgets('Vedi tutte apre la pagina e Indietro torna', (tester) async {
      await pumpSearch(tester);

      await tester.tap(find.text('Vedi tutte'));
      await tester.pump();
      await tester.pump();
      expect(router.state.uri.toString(), '/people?q=ist');
      expect(find.byType(PeopleSearchScreen), findsOneWidget);

      router.pop();
      await tester.pump();
      await tester.pump();
      expect(router.state.uri.toString(), '/search');
    });

    testWidgets('sul telefono: "Vedi tutte le 150 persone"', (tester) async {
      await pumpSearch(tester, size: const Size(390, 780), touch: true);

      final seeAll = find.text('Vedi tutte le 150 persone');
      expect(seeAll, findsOneWidget);
      await tester.tap(seeAll);
      await tester.pump();
      await tester.pump();
      expect(router.state.uri.toString(), '/people?q=ist');
    });
  });
}
