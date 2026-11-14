import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_genre_index.dart';
import 'package:wonderflix/features/catalog/catalog_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/skeletons.dart';
import 'package:wonderflix/ui/states.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  /// Le richieste della griglia (i conteggi chiedono `limit` 0).
  late List<ItemQuery> gridQueries;

  setUp(() {
    gridQueries = [];
    api = FakeLibraryApi()
      ..libraryFilters = const LibraryFilters(genres: ['Dramma'], years: [2024]);
    api.onItems = (query, start, limit) {
      if (limit > 0) gridQueries.add(query);
      return query.watched == WatchedFilter.unwatched
          ? pageOf([])
          : pageOf([
              testItem(id: 'm1', name: 'Dune'),
              testItem(id: 'm2', name: 'Alien'),
            ]);
    };
  });

  // Il centro della riga intera è vuoto: si guarda la voce "Tutti".
  final allGenres = find.descendant(
      of: find.byType(CatalogGenreIndex), matching: find.text('Tutti'));

  Future<void> pumpCatalog(WidgetTester tester,
      {String? genre,
      MotionLevel motion = MotionLevel.reduced,
      bool tv = false,
      Size surfaceSize = const Size(1440, 900),
      SocialFeatures features = SocialFeatures.none}) async {
    // In app la schermata vive dentro lo Scaffold dell'AppShell (serve un
    // antenato Material per i menu).
    await pumpApp(
        tester,
        Scaffold(body: CatalogScreen(kind: ItemKind.movie, genre: genre)),
        motion: motion,
        tv: tv,
        surfaceSize: surfaceSize,
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          // Anche la sessione con l'utente di prova.
          ...socialTestOverrides(FakeSocialApi(), features: features),
        ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('senza genere: Tutti i film, ordine Aggiunti, griglia',
      (tester) async {
    await pumpCatalog(tester);
    expect(find.text('Tutti i film'), findsWidgets);
    expect(find.text('Ordina: Aggiunti'), findsOneWidget);
    expect(find.textContaining('Gli ultimi arrivati per primi'), findsWidgets);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Alien'), findsOneWidget);
    expect(gridQueries.single.genres, isEmpty);
  });

  testWidgets('con un genere: titolo del genere, una sola richiesta',
      (tester) async {
    await pumpCatalog(tester, genre: 'Horror');
    expect(find.text('Horror'), findsWidgets);
    expect(gridQueries, hasLength(1));
    expect(gridQueries.single.genres, contains('Horror'));
    expect(gridQueries.single.sort, CatalogSort.rating);
  });

  testWidgets('desktop: dopo uno scroll la riga dei generi resta visibile',
      (tester) async {
    api.onItems = (query, start, limit) => pageOf(
        [for (var i = 0; i < 60; i++) testItem(id: 'm$i', name: 'T$i')]);
    await pumpCatalog(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pump();
    expect(find.text('T0').hitTestable(), findsNothing);
    expect(allGenres.hitTestable(), findsOneWidget);
    // Ferma sotto la barra in alto (64), non sotto il bordo della finestra.
    expect(tester.getTopLeft(find.byType(CatalogGenreIndex)).dy,
        moreOrLessEquals(64));
  });

  testWidgets('TV: la riga dei generi esce con il cartellone', (tester) async {
    api.onItems = (query, start, limit) => pageOf(
        [for (var i = 0; i < 60; i++) testItem(id: 'm$i', name: 'T$i')]);
    await pumpCatalog(tester, tv: true, surfaceSize: const Size(960, 540));
    expect(allGenres.hitTestable(), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pump();
    expect(allGenres.hitTestable(), findsNothing);
  });

  testWidgets('vuoto con un genere: testo del genere e Azzera filtri',
      (tester) async {
    await pumpCatalog(tester, genre: 'Horror');
    await tester.tap(find.text('Nascondi i visti'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nessun film di questo genere con questi filtri.'),
        findsOneWidget);
    expect(gridQueries.last.watched, WatchedFilter.unwatched);

    await tester.tap(find.text('Azzera filtri').last);
    await tester.pump();
    await tester.pump();
    expect(gridQueries.last.watched, WatchedFilter.all);
    expect(gridQueries.last.genres, contains('Horror'));
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('vuoto senza genere: Nessun film con questi filtri',
      (tester) async {
    await pumpCatalog(tester);
    await tester.tap(find.text('Nascondi i visti'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nessun film con questi filtri.'), findsOneWidget);
  });

  testWidgets('primo caricamento: il titolo del genere sopra lo scheletro',
      (tester) async {
    final gate = Completer<void>();
    api.itemsGateFor = (query) => gate;
    await pumpCatalog(tester, genre: 'Western');
    expect(find.text('Western'), findsWidgets);
    expect(find.byType(PosterGridSkeleton), findsOneWidget);
    expect(tester.getTopLeft(find.byType(PosterGridSkeleton)).dy,
        greaterThan(tester.getTopLeft(find.text('Western').first).dy));
    gate.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('cambiando un filtro il nuovo stato entra in dissolvenza',
      (tester) async {
    await pumpCatalog(tester, motion: MotionLevel.full);
    await tester.pump(const Duration(seconds: 1));
    double opacity() => tester
        .widget<SliverFadeTransition>(find.byType(SliverFadeTransition))
        .opacity
        .value;
    expect(opacity(), 1);

    await tester.tap(find.text('Nascondi i visti'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(opacity(), lessThan(1));
    await tester.pump(const Duration(seconds: 1));
    expect(opacity(), 1);
    expect(find.text('Nessun film con questi filtri.'), findsOneWidget);
  });

  testWidgets('riscegliere la voce già scelta non ricarica il catalogo',
      (tester) async {
    await pumpCatalog(tester);
    expect(gridQueries, hasLength(1));
    await tester.tap(find.text('Ordina: Aggiunti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina: Aggiunti').last);
    await tester.pumpAndSettle();
    expect(gridQueries, hasLength(1));
  });

  testWidgets('errore con riprova', (tester) async {
    api.error = const ServerUnreachableException();
    await pumpCatalog(tester);
    expect(find.byType(ErrorView), findsOneWidget);
    api.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('schede Film / Saghe solo con la funzione delle saghe',
      (tester) async {
    await pumpCatalog(tester);
    expect(find.byKey(const ValueKey('catalog-view-titles')), findsNothing);
    expect(find.text('Saghe'), findsNothing);
  });

  testWidgets('con la funzione delle saghe: le due schede', (tester) async {
    await pumpCatalog(tester,
        features: const SocialFeatures(collections: true));
    expect(find.byKey(const ValueKey('catalog-view-titles')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-view-sagas')), findsOneWidget);
  });

  testWidgets('cambiando il genere sulla stessa schermata ricarica il catalogo',
      (tester) async {
    final genre = ValueNotifier<String?>('Dramma');
    addTearDown(genre.dispose);
    await pumpApp(
        tester,
        ValueListenableBuilder<String?>(
            valueListenable: genre,
            builder: (_, g, _) => Scaffold(
                body: CatalogScreen(
                    key: const ValueKey('movies'),
                    kind: ItemKind.movie,
                    genre: g))),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ]);
    await tester.pump();
    await tester.pump();
    expect(gridQueries.last.genres, contains('Dramma'));

    genre.value = 'Commedia';
    await tester.pump();
    await tester.pump();
    expect(gridQueries.last.genres, contains('Commedia'));
    expect(gridQueries.last.genres, isNot(contains('Dramma')));

    genre.value = null;
    await tester.pump();
    await tester.pump();
    expect(gridQueries.last.genres, isEmpty);
  });

  testWidgets('pagina che non riempie la finestra: carica la successiva',
      (tester) async {
    // Due titoli per richiesta su 4 totali: la finestra non si riempie mai,
    // quindi senza scroll il caricamento successivo deve partire da solo.
    api.onItems = (query, start, limit) {
      if (limit > 0) gridQueries.add(query);
      return pageOf([
        for (var i = start; i < start + 2; i++) testItem(id: 'm$i', name: 'T$i')
      ], 4);
    };
    await pumpCatalog(tester);
    await tester.pump();
    await tester.pump();
    expect(gridQueries, hasLength(2));
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
    expect(find.byType(PosterCard), findsNWidgets(3));
  });
}
