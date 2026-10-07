import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/detail/movie_detail_view.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  testWidgets(
      'l\'id di una saga apre la pagina della saga, al posto della scheda',
      (tester) async {
    // Un link della cassetta o del registro attività può portare qui l'id di
    // una saga.
    final api = FakeLibraryApi()
      ..itemsById['c1'] = testItem(
          id: 'c1',
          name: 'Matrix - Collezione',
          kind: ItemKind.boxSet,
          year: null,
          runtimeMinutes: null);
    final router = GoRouter(initialLocation: '/item/c1', routes: [
      GoRoute(
          path: '/item/:id',
          builder: (context, state) => Scaffold(
              body: ItemDetailScreen(itemId: state.pathParameters['id']!))),
      GoRoute(
          path: '/collection/:id',
          builder: (context, state) =>
              Scaffold(body: Text('saga ${state.pathParameters['id']}'))),
    ]);
    await pumpAppRouter(tester, router, overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    // Lo scheletro ha un'onda continua: si avanza a passi, senza
    // `pumpAndSettle`.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('saga c1'), findsOneWidget);
    expect(find.byType(ItemDetailScreen), findsNothing);
    expect(find.byType(MovieDetailView), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/collection/c1');
    // La scheda è stata sostituita, non coperta: indietro non ci torna.
    expect(router.canPop(), isFalse);
  });

  testWidgets('mentre la saga passa alla sua pagina non si vede un film',
      (tester) async {
    final api = FakeLibraryApi()
      ..delay = const Duration(milliseconds: 50)
      ..itemsById['c1'] = testItem(
          id: 'c1',
          name: 'Matrix - Collezione',
          kind: ItemKind.boxSet,
          year: null,
          runtimeMinutes: null,
          overview: 'Due realtà.');
    final router = GoRouter(initialLocation: '/item/c1', routes: [
      GoRoute(
          path: '/item/:id',
          builder: (context, state) => Scaffold(
              body: ItemDetailScreen(itemId: state.pathParameters['id']!))),
      GoRoute(
          path: '/collection/:id',
          builder: (context, state) =>
              Scaffold(body: Text('saga ${state.pathParameters['id']}'))),
    ]);
    await pumpAppRouter(tester, router, overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    // La saga è arrivata (e la rotta sta per cambiare): né titolo né trama
    // di una scheda.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.byType(MovieDetailView), findsNothing);
    expect(find.text('Due realtà.'), findsNothing);
    expect(find.text('MATRIX - COLLEZIONE'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('saga c1'), findsOneWidget);
  });
}
