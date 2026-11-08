import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/poster_card.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..libraryFilters = const LibraryFilters(genres: ['Dramma'], years: [2024])
      ..onItems = (query, start, limit) => query.watched == WatchedFilter.watched
          ? pageOf([])
          : pageOf([testItem(id: 'm1', name: 'Dune'), testItem(id: 'm2', name: 'Alien')]);
  });

  Future<void> pumpCatalog(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    // In app la schermata vive dentro lo Scaffold dell'AppShell (serve un
    // antenato Material per DropdownButton/SegmentedButton).
    await pumpApp(
        tester, const Scaffold(body: CatalogScreen(kind: ItemKind.movie)),
        motion: motion,
        overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('TV a 960×540: filtri in una riga, la griglia riempie lo schermo',
      (tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: CatalogScreen(kind: ItemKind.movie)),
      tv: true,
      surfaceSize: const Size(960, 540),
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        // Con le saghe: anche la riga Film / Saghe.
        ...socialTestOverrides(
          FakeSocialApi(),
          features: const SocialFeatures(collections: true),
        ),
      ],
    );
    await tester.pump();
    await tester.pump();

    double top(Finder f) => tester.getTopLeft(f).dy;
    final filters = [
      find.text('Ordina per: Titolo'),
      find.text('Tutti i generi'),
      find.text('Tutti gli anni'),
      find.text('Visti'),
    ];
    // Una riga sola: i centri dei controlli stanno alla stessa altezza.
    final centers = {
      for (final f in filters) tester.getCenter(f).dy.round(),
    };
    expect(centers, hasLength(1));
    // La griglia parte nel terzo alto dello schermo.
    expect(top(find.byType(PosterCard).first), lessThan(540 / 3));
  });

  testWidgets('titolo, conteggio e griglia', (tester) async {
    await pumpCatalog(tester);
    expect(find.text('FILM'), findsOneWidget);
    expect(find.text('2 titoli'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Alien'), findsOneWidget);
  });

  testWidgets('filtro "Visti" senza risultati e azzeramento', (tester) async {
    await pumpCatalog(tester);
    await tester.tap(find.text('Visti'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nessun titolo con questi filtri.'), findsOneWidget);
    expect(api.itemQueries.last.watched, WatchedFilter.watched);

    await tester.tap(find.text('Azzera filtri').last);
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('menu dei generi con i generi del server', (tester) async {
    await pumpCatalog(tester);
    await tester.tap(find.text('Tutti i generi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dramma').last);
    await tester.pumpAndSettle();
    expect(api.itemQueries.last.genres, {'Dramma'});
  });

  testWidgets('riscegliere la voce già scelta non ricarica il catalogo',
      (tester) async {
    await pumpCatalog(tester);
    expect(api.itemQueries, hasLength(1));
    // L'ordinamento di partenza è per titolo.
    await tester.tap(find.text('Ordina per: Titolo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina per: Titolo').last);
    await tester.pumpAndSettle();
    expect(api.itemQueries, hasLength(1));
  });

  testWidgets('errore con riprova', (tester) async {
    api.error = const ServerUnreachableException();
    await pumpCatalog(tester);
    expect(find.text('Riprova'), findsOneWidget);
    api.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('pagina che non riempie la finestra: carica la successiva',
      (tester) async {
    // Due titoli per richiesta su 4 totali: la finestra non si riempie mai,
    // quindi senza scroll il caricamento successivo deve partire da solo.
    api.onItems = (query, start, limit) => pageOf(
        [for (var i = start; i < start + 2; i++) testItem(id: 'm$i', name: 'T$i')],
        4);
    await pumpCatalog(tester);
    await tester.pump();
    await tester.pump();
    expect(api.itemQueries, hasLength(2));
    expect(find.text('T3'), findsOneWidget);
  });

  testWidgets('completa: le card della prima pagina entrano scaglionate',
      (tester) async {
    api.onItems = (query, start, limit) => pageOf([
          testItem(id: 'm1', name: 'Dune'),
          testItem(id: 'm2', name: 'Alien'),
          testItem(id: 'm3', name: 'Heat'),
        ]);
    await pumpCatalog(tester, motion: MotionLevel.full);
    double opacityOf(String text) => tester
        .widget<Opacity>(find
            .ancestor(of: find.text(text), matching: find.byType(Opacity))
            .first)
        .opacity;
    expect(opacityOf('Dune'), lessThan(1));
    // Niente pumpAndSettle: lo scheletro che sfuma ha l'onda continua.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(opacityOf('Dune'), 1);
    expect(opacityOf('Heat'), 1);
  });
}
