import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/search/search_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';
import '../../support/test_data.dart';

void main() {
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
    ]);

    expect(find.text('Scrivi almeno 2 lettere per cercare.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Serie'), findsNothing);
  });

  testWidgets('nessun risultato', (tester) async {
    final api = FakeLibraryApi();
    await pumpApp(tester, const Scaffold(body: SearchScreen()), overrides: [
      libraryApiProvider.overrideWithValue(api),
      requestsAvailableProvider.overrideWithValue(false),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Nessun risultato per "zzz"'), findsOneWidget);
  });

  List<Override> overrides(FakeLibraryApi library, FakeRequestsApi requests,
          {bool available = true}) =>
      [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
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
    expect(find.text('Non sono ancora su WonderFlix'), findsOneWidget);
    expect(find.text('Dune - Parte due'), findsOneWidget);
    expect(find.text('Dune: Prophecy'), findsOneWidget);
    expect(find.text('Richiesto'), findsOneWidget);
    // "Film" è il titolo della sezione della libreria e l'etichetta della card.
    expect(find.text('Film'), findsNWidgets(2));
    // Dune c'è una volta sola: la card della libreria.
    expect(find.text('Dune'), findsOneWidget);
    expect(requests.searchLanguages, ['it']);
  });

  testWidgets('Seerr giù: messaggio e Riprova, la libreria resta', (tester) async {
    final requests = FakeRequestsApi()..failure = RequestsFailure.seerrUnavailable;
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests));

    await search(tester, 'dune');

    expect(find.text('Seerr non risponde'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);

    requests
      ..failure = null
      ..searchResults['dune'] = [testRequestable(title: 'Dune - Parte due')];
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
}
