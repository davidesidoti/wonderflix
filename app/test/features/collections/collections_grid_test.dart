import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_genre_index.dart';
import 'package:wonderflix/features/catalog/catalog_navigation.dart';
import 'package:wonderflix/features/catalog/catalog_screen.dart';
import 'package:wonderflix/features/catalog/catalog_band.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/collections/saga_fan_card.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/skeletons.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeCollectionsApi collections;

  setUp(() {
    library = FakeLibraryApi()
      ..onItems = (query, start, limit) =>
          pageOf([testItem(id: 'm1', name: 'Dune')]);
    collections = FakeCollectionsApi()
      ..collectionsList = [
        testCollection(
            id: 'c1',
            name: 'Matrix - Collezione',
            itemIds: ['m1', 'm2', 'm3'],
            dateCreated: DateTime.utc(2026, 1, 1)),
        testCollection(
            id: 'c2',
            name: 'Alien - Collezione',
            itemIds: ['m4', 'm5'],
            dateCreated: DateTime.utc(2026, 6, 1)),
      ];
  });

  Future<void> pumpCatalog(WidgetTester tester, String location,
      {SocialFeatures features = const SocialFeatures(collections: true),
      bool tv = false,
      Size surfaceSize = const Size(1440, 900)}) async {
    final router = GoRouter(initialLocation: location, routes: [
      GoRoute(
        path: '/movies',
        builder: (context, state) => Scaffold(
          body: CatalogScreen(
            key: const ValueKey('movies'),
            kind: ItemKind.movie,
            view: CatalogView.parse(state.uri.queryParameters['view']),
          ),
        ),
      ),
      GoRoute(
          path: '/collection/:id',
          builder: (context, state) =>
              Scaffold(body: Text('saga ${state.pathParameters['id']}'))),
    ]);
    await pumpAppRouter(tester, router, tv: tv, surfaceSize: surfaceSize, overrides: [
      libraryApiProvider.overrideWithValue(library),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
      collectionsApiProvider.overrideWithValue(collections),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('il selettore porta dai film alle saghe', (tester) async {
    await pumpCatalog(tester, '/movies');
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Saghe'), findsOneWidget);

    await tester.tap(find.text('Saghe'));
    await tester.pump();
    await tester.pump();
    expect(find.text('2 saghe, 0 finite.'), findsOneWidget);
    expect(find.text('Matrix'), findsOneWidget);
    expect(find.text('3 film'), findsOneWidget);
    expect(find.byType(CatalogGenreIndex), findsNothing,
        reason: 'generi e anni non valgono per le saghe');
  });

  testWidgets('senza la funzione: niente selettore, ?view=sagas mostra i film',
      (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas',
        features: SocialFeatures.none);
    expect(find.text('Saghe'), findsNothing);
    expect(find.text('Dune'), findsOneWidget);
    expect(collections.calls, 0);
  });

  testWidgets('ricerca per nome e ordinamento', (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas');
    // Per nome: Alien prima di Matrix.
    expect(tester.getTopLeft(find.text('Alien')).dx,
        lessThan(tester.getTopLeft(find.text('Matrix')).dx));

    await tester.tap(find.text('Ordina: Nome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina: Numero di film').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Matrix')).dx,
        lessThan(tester.getTopLeft(find.text('Alien')).dx));

    await tester.enterText(
        find.byKey(const Key('collections-search')), 'ALIEN');
    await tester.pumpAndSettle();
    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Matrix'), findsNothing);

    await tester.enterText(find.byKey(const Key('collections-search')), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('Nessuna saga con questo nome'), findsOneWidget);
  });

  testWidgets('clic su una saga: la sua pagina', (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas');
    await tester.tap(find.text('Matrix'));
    await tester.pumpAndSettle();
    expect(find.text('saga c1'), findsOneWidget);
  });

  testWidgets('nessuna saga', (tester) async {
    collections.collectionsList = [];
    await pumpCatalog(tester, '/movies?view=sagas');
    expect(find.text('Nessuna saga'), findsOneWidget);
  });

  testWidgets('errore con Riprova', (tester) async {
    collections.error = const ServerUnreachableException();
    await pumpCatalog(tester, '/movies?view=sagas');
    expect(find.text('Riprova'), findsOneWidget);

    collections.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Matrix'), findsOneWidget);
  });

  testWidgets('in caricamento: lo scheletro, non "Nessuna saga"',
      (tester) async {
    final gate = Completer<void>();
    collections.gate = gate;
    await pumpCatalog(tester, '/movies?view=sagas');
    expect(find.byType(PosterGridSkeleton), findsOneWidget);
    expect(find.text('Nessuna saga'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();
    // Lo scheletro esce in dissolvenza.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PosterGridSkeleton), findsNothing);
    expect(find.text('Matrix'), findsOneWidget);
  });

  testWidgets('Riprova: lo scheletro finché non arrivano le saghe',
      (tester) async {
    collections.error = const ServerUnreachableException();
    await pumpCatalog(tester, '/movies?view=sagas');
    expect(find.text('Riprova'), findsOneWidget);

    collections.error = null;
    final gate = Completer<void>();
    collections.gate = gate;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprova'), findsNothing);
    expect(find.byType(PosterGridSkeleton), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Matrix'), findsOneWidget);
  });

  testWidgets('la funzione che da sconosciuta diventa nota: lo scheletro',
      (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas',
        features: SocialFeatures.none);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(CatalogScreen)));
    // Altrove (la scheda di un film, la ricerca) l'elenco è già in uso: senza
    // la funzione è vuoto, e arrivata la funzione si rilegge.
    final subscription = container.listen(collectionsProvider, (_, _) {});
    await tester.pump();
    expect(collections.calls, 0);

    final gate = Completer<void>();
    collections.gate = gate;
    (container.read(socialAvailabilityProvider.notifier)
            as FakeSocialAvailability)
        .set(const SocialFeatures(collections: true));
    await tester.pump();
    await tester.pump();
    expect(find.byType(PosterGridSkeleton), findsOneWidget);
    expect(find.text('Nessuna saga'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Matrix'), findsOneWidget);
    subscription.close();
  });

  testWidgets(
      'la funzione che da sconosciuta diventa nota ma la lettura fallisce: '
      'Riprova, non "Nessuna saga"', (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas',
        features: SocialFeatures.none);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(CatalogScreen)));
    // Come sopra: l'elenco vuoto di prima è ancora lì, sotto l'errore.
    final subscription = container.listen(collectionsProvider, (_, _) {});
    await tester.pump();
    expect(collections.calls, 0);

    collections.error = const ServerUnreachableException();
    (container.read(socialAvailabilityProvider.notifier)
            as FakeSocialAvailability)
        .set(const SocialFeatures(collections: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprova'), findsOneWidget);
    expect(find.text('Nessuna saga'), findsNothing);
    subscription.close();
  });

  testWidgets('il selettore riporta dalle saghe ai film', (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas');
    expect(find.text('Dune'), findsNothing);
    expect(find.text('Matrix'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('catalog-view-titles')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.byType(CatalogGenreIndex), findsOneWidget);
    expect(find.text('Matrix'), findsNothing);
  });

  testWidgets('una nuova ricerca o un nuovo ordine riparte dall\'inizio',
      (tester) async {
    collections.collectionsList = [
      for (var i = 0; i < 40; i++)
        testCollection(id: 'c$i', name: 'Saga ${'$i'.padLeft(2, '0')}'),
    ];
    await pumpCatalog(tester, '/movies?view=sagas');
    final scrollable = find.descendant(
        of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;
    double offset() => tester.state<ScrollableState>(scrollable).position.pixels;
    // Si torna a dove il cartellone è appena chiuso: gli attrezzi restano
    // fermi in cima.
    final band = tester.getSize(find.byType(CatalogBand)).height;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    expect(offset(), greaterThan(band));
    await tester.enterText(find.byKey(const Key('collections-search')), 'saga');
    await tester.pump();
    expect(offset(), lessThan(band));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    expect(offset(), greaterThan(band));
    await tester.tap(find.text('Ordina: Nome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina: Numero di film').last);
    await tester.pumpAndSettle();
    expect(offset(), lessThan(band));
  });

  Finder goldSegments(Finder card) => find.descendant(
      of: card,
      matching: find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color == WfColors.gold));

  Finder segments(Finder card) => find.descendant(
      of: card,
      matching: find.byKey(const ValueKey('saga-segment')));

  testWidgets('la card: nome ripulito, film visti e un tratto per film',
      (tester) async {
    collections.collectionsList = [
      testCollection(
          id: 'c1', name: 'Avengers - Collezione', itemIds: ['m1', 'm2', 'm3', 'm4']),
    ];
    library.itemsById
      ..['m1'] = testItem(id: 'm1', played: true)
      ..['m2'] = testItem(id: 'm2', played: true)
      ..['m3'] = testItem(id: 'm3', played: true)
      ..['m4'] = testItem(id: 'm4');
    await pumpCatalog(tester, '/movies?view=sagas');
    await tester.pump();
    final card = find.byType(SagaFanCard);
    expect(find.text('Avengers'), findsOneWidget);
    expect(find.text('4 film, 3 visti'), findsOneWidget);
    expect(segments(card), findsNWidgets(4));
    expect(goldSegments(card), findsNWidgets(3));
    expect(tester.getSize(segments(card).first).height, 3);
    // Tre locandine a ventaglio: la centrale più in alto.
    final posters = find.descendant(of: card, matching: find.byType(WfImage));
    expect(posters, findsNWidgets(3));
  });

  testWidgets('la card: tutti visti, nessuno visto', (tester) async {
    collections.collectionsList = [
      testCollection(id: 'c1', name: 'Alien', itemIds: ['m1']),
      testCollection(id: 'c2', name: 'Batman', itemIds: ['m2', 'm3']),
    ];
    library.itemsById
      ..['m1'] = testItem(id: 'm1', played: true)
      ..['m2'] = testItem(id: 'm2')
      ..['m3'] = testItem(id: 'm3');
    await pumpCatalog(tester, '/movies?view=sagas');
    await tester.pump();
    expect(find.text('1 film, tutti visti'), findsOneWidget);
    expect(find.text('2 film, nessuno visto'), findsOneWidget);
    expect(find.text('2 saghe, 1 finita.'), findsOneWidget);
  });

  testWidgets('"Nascondi le saghe finite" toglie quelle tutte viste',
      (tester) async {
    library.itemsById
      ..['m1'] = testItem(id: 'm1', played: true)
      ..['m2'] = testItem(id: 'm2')
      ..['m4'] = testItem(id: 'm4', played: true)
      ..['m5'] = testItem(id: 'm5', played: true);
    await pumpCatalog(tester, '/movies?view=sagas');
    await tester.pump();
    expect(find.text('Alien'), findsOneWidget);

    await tester.tap(find.text('Nascondi le saghe finite'));
    await tester.pumpAndSettle();
    expect(find.text('Alien'), findsNothing);
    expect(find.text('Matrix'), findsOneWidget);
  });

  testWidgets('senza i film delle saghe: la locandina della saga, niente barra',
      (tester) async {
    library.itemsByIdsGate = Completer<void>();
    await pumpCatalog(tester, '/movies?view=sagas');
    final card = find.widgetWithText(SagaFanCard, 'Matrix');
    expect(find.descendant(of: card, matching: find.text('3 film')),
        findsOneWidget);
    expect(segments(card), findsNothing);
    final poster = tester.widget<WfImage>(
        find.descendant(of: card, matching: find.byType(WfImage)));
    expect(poster.image!.url, contains('/Items/c1/Images/Primary'));
    library.itemsByIdsGate!.complete();
  });

  testWidgets('il cartellone: fondale del primo film della saga più recente',
      (tester) async {
    library.itemsById['m4'] = JellyfinItem.fromJson({
      'Id': 'm4',
      'Name': 'Alien',
      'Type': 'Movie',
      'BackdropImageTags': ['b4'],
    });
    await pumpCatalog(tester, '/movies?view=sagas');
    await tester.pump();
    expect(tester.widget<CatalogBand>(find.byType(CatalogBand)).hero?.id, 'm4');
  });

  testWidgets('telefono e TV: le card stanno nelle celle; sulla TV niente '
      'ricerca', (tester) async {
    library.itemsById
      ..['m1'] = testItem(id: 'm1', played: true)
      ..['m4'] = testItem(id: 'm4');
    await pumpCatalog(tester, '/movies?view=sagas',
        surfaceSize: const Size(390, 844));
    await tester.pump();
    expect(find.text('1 film, tutti visti'), findsOneWidget);
    expect(find.byKey(const Key('collections-search')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpCatalog(tester, '/movies?view=sagas',
        tv: true, surfaceSize: const Size(960, 540));
    await tester.pump();
    expect(find.text('Nascondi le saghe finite'), findsOneWidget);
    expect(find.byKey(const Key('collections-search')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
