import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_navigation.dart';
import 'package:wonderflix/features/catalog/catalog_screen.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/skeletons.dart';

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
      {SocialFeatures features = const SocialFeatures(collections: true)}) async {
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
    await pumpAppRouter(tester, router, overrides: [
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
    expect(find.text('2 saghe'), findsOneWidget);
    expect(find.text('Matrix - Collezione'), findsOneWidget);
    expect(find.text('3 film'), findsOneWidget);
    expect(find.text('Tutti i generi'), findsNothing,
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
    expect(tester.getTopLeft(find.text('Alien - Collezione')).dx,
        lessThan(tester.getTopLeft(find.text('Matrix - Collezione')).dx));

    await tester.tap(find.text('Ordina per: Nome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina per: Numero di film').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Matrix - Collezione')).dx,
        lessThan(tester.getTopLeft(find.text('Alien - Collezione')).dx));

    await tester.enterText(
        find.byKey(const Key('collections-search')), 'ALIEN');
    await tester.pumpAndSettle();
    expect(find.text('Alien - Collezione'), findsOneWidget);
    expect(find.text('Matrix - Collezione'), findsNothing);

    await tester.enterText(find.byKey(const Key('collections-search')), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('Nessuna saga con questo nome'), findsOneWidget);
  });

  testWidgets('clic su una saga: la sua pagina', (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas');
    await tester.tap(find.text('Matrix - Collezione'));
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
    expect(find.text('Matrix - Collezione'), findsOneWidget);
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
    expect(find.text('Matrix - Collezione'), findsOneWidget);
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
    expect(find.text('Matrix - Collezione'), findsOneWidget);
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
    expect(find.text('Matrix - Collezione'), findsOneWidget);
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
    expect(find.text('Matrix - Collezione'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('catalog-view-titles')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Tutti i generi'), findsOneWidget);
    expect(find.text('Matrix - Collezione'), findsNothing);
  });

  testWidgets('una nuova ricerca o un nuovo ordine riparte dall\'inizio',
      (tester) async {
    collections.collectionsList = [
      for (var i = 0; i < 40; i++)
        testCollection(id: 'c$i', name: 'Saga ${'$i'.padLeft(2, '0')}'),
    ];
    await pumpCatalog(tester, '/movies?view=sagas');
    final scrollable = find.descendant(
        of: find.byType(CustomScrollView), matching: find.byType(Scrollable));
    double offset() => tester.state<ScrollableState>(scrollable).position.pixels;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    expect(offset(), greaterThan(0));
    await tester.enterText(find.byKey(const Key('collections-search')), 'saga');
    await tester.pump();
    expect(offset(), 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    expect(offset(), greaterThan(0));
    await tester.tap(find.text('Ordina per: Nome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina per: Numero di film').last);
    await tester.pumpAndSettle();
    expect(offset(), 0);
  });
}
