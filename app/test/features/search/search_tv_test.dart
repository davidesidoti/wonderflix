import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/search/search_screen.dart';
import 'package:wonderflix/ui/media_row.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/tv_focusable.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

/// Lo schermo che vede l'app sul Fire Stick.
const _tvSize = Size(960, 540);

void main() {
  late SharedPreferences prefs;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'search.recent.${testUser.id}': ['dune'],
    });
    prefs = await SharedPreferences.getInstance();
    router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (_, _) => const Scaffold(body: SearchScreen()),
        ),
        GoRoute(path: '/item/:id', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/movies', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/series', builder: (_, _) => const SizedBox()),
      ],
    );
  });

  /// Film: 15 di totale, 7 in risposta; serie: tre, la migliore "L'Istituto".
  FakeLibraryApi library() => FakeLibraryApi()
    ..libraryFilters = const LibraryFilters(genres: ['Dramma'])
    ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
        ? pageOf([
            testItem(id: 'm0', name: 'Il mistero della pietra'),
            for (var i = 1; i < 7; i++)
              testItem(id: 'm$i', name: 'Cristallo $i'),
          ], 15)
        : pageOf([
            testItem(id: 's0', name: "L'Istituto", kind: ItemKind.series),
            testItem(
              id: 's1',
              name: "Marvel's Iron Fist",
              kind: ItemKind.series,
            ),
            testItem(id: 's2', name: 'Mistica', kind: ItemKind.series),
          ]))
    ..people = [];

  Future<void> pumpSearch(WidgetTester tester) async {
    await pumpAppRouter(
      tester,
      router,
      tv: true,
      surfaceSize: _tvSize,
      overrides: [
        libraryApiProvider.overrideWithValue(library()),
        requestsAvailableProvider.overrideWithValue(false),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    await tester.pump();
  }

  Future<void> search(WidgetTester tester, String term) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.enterText(find.byType(TextField), term);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  Finder row(String title) =>
      find.byWidgetPredicate((w) => w is MediaRow && w.title == title);

  bool focused(WidgetTester tester, Finder finder) =>
      Focus.of(tester.element(finder)).hasFocus;

  testWidgets('TV: prima di scrivere due file, focus sulla cornice', (
    tester,
  ) async {
    await pumpSearch(tester);

    expect(find.text('Ricerche recenti'), findsOneWidget);
    expect(find.text('Prova con un genere'), findsOneWidget);
    expect(find.text('Aggiunti di recente'), findsNothing);
    expect(find.byType(InputChip), findsNothing, reason: 'niente ✕');
    expect(find.widgetWithText(ActionChip, 'Dramma'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // la cornice
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester, find.text('dune')), isTrue);

    // "Cancella" è l'ultima della fila dei recenti.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focused(tester, find.text('Cancella')), isTrue);

    // Giù: la fila dei generi, prima Film.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester, find.text('Film')), isTrue);

    // Su torna alla prima pastiglia dei recenti; OK la cerca.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Ricerche recenti'), findsNothing);
  });

  testWidgets('TV: il miglior risultato è la prima carta della sua fila', (
    tester,
  ) async {
    await pumpSearch(tester);
    await search(tester, 'ist');

    final series = row('Serie');
    expect(series, findsOneWidget);
    expect(find.text('Miglior risultato'), findsOneWidget);
    final best = find.descendant(
      of: series,
      matching: find.text('Miglior risultato'),
    );
    expect(best, findsOneWidget);
    final posters = find.descendant(
      of: series,
      matching: find.byType(PosterCard),
    );
    expect(posters, findsNWidgets(2));
    expect(
      tester.getTopLeft(best).dx,
      lessThan(tester.getTopLeft(posters.first).dx),
    );
    expect(
      find.descendant(
        of: series,
        matching: find.text("L'Istituto", findRichText: true),
      ),
      findsOneWidget,
    );
    // Serie prima di Film: la fila col miglior risultato.
    expect(
      tester.getTopLeft(series).dy,
      lessThan(tester.getTopLeft(row('Film')).dy),
    );

    // OK sulla carta apre la scheda.
    final card = find
        .descendant(of: series, matching: find.byType(TvFocusable))
        .first;
    Focus.of(
      tester.element(
        find.descendant(
          of: card,
          matching: find.text("L'Istituto", findRichText: true),
        ),
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(router.state.uri.toString(), '/item/s0');
  });

  testWidgets('TV: l\'ultima carta di una fila tagliata è Vedi tutti', (
    tester,
  ) async {
    await pumpSearch(tester);
    await search(tester, 'ist');

    final films = row('Film');
    await tester.scrollUntilVisible(
      find.text('Vedi tutti'),
      200,
      scrollable: find
          .descendant(of: films, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pump();
    expect(
      find.descendant(of: films, matching: find.text('Vedi tutti')),
      findsOneWidget,
    );
    final last = find.descendant(
      of: films,
      matching: find.byWidgetPredicate(
        (w) => w is PosterCard && w.item.id == 'm6',
      ),
    );
    expect(
      tester.getTopLeft(find.text('Vedi tutti')).dx,
      greaterThan(tester.getTopLeft(last).dx),
    );

    final seeAll = find.ancestor(
      of: find.text('Vedi tutti'),
      matching: find.byType(TvFocusable),
    );
    expect(seeAll, findsOneWidget);
    Focus.of(tester.element(find.text('Vedi tutti'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(router.state.uri.toString(), '/movies?q=ist');
    expect(prefs.getStringList('search.recent.${testUser.id}'), [
      'ist',
      'dune',
    ]);
  });

  testWidgets('TV: nessun overflow a 960×540', (tester) async {
    await pumpSearch(tester);
    expect(tester.takeException(), isNull);
    await search(tester, 'ist');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
