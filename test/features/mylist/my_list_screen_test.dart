import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_filters_bar.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';
import 'package:wonderflix/ui/card_preview.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  List<JellyfinItem> library() => [
        testItem(
            id: 'd',
            name: 'Dune',
            year: 2021,
            genres: ['Fantascienza'],
            favorite: true,
            dateCreated: '2024-05-01T00:00:00Z'),
        testItem(
            id: 'h',
            name: 'Heat',
            year: 1995,
            genres: ['Crimine'],
            favorite: true,
            played: true,
            dateCreated: '2023-01-01T00:00:00Z'),
        testItem(
            id: 'a',
            name: 'Arrival',
            year: 2016,
            genres: ['Fantascienza'],
            favorite: true,
            dateCreated: '2022-01-01T00:00:00Z'),
      ];

  FakeLibraryApi apiWith(List<JellyfinItem> items) => FakeLibraryApi()
    ..onItems = (query, start, limit) =>
        query.favoritesOnly ? pageOf(items) : pageOf([]);

  double xOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dx;

  Future<FakeLibraryApi> pumpList(WidgetTester tester, FakeLibraryApi api) async {
    await pumpApp(tester, const Scaffold(body: MyListScreen()), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();
    return api;
  }

  testWidgets('mostra i preferiti', (tester) async {
    final api = await pumpList(
        tester,
        FakeLibraryApi()
          ..onItems = (query, start, limit) => query.favoritesOnly
              ? pageOf([testItem(id: 'm1', name: 'Dune', favorite: true)])
              : pageOf([]));
    // Lo scheletro ha già il titolo: finita la dissolvenza ne resta uno.
    await tester.pumpAndSettle();
    expect(find.text('LA MIA LISTA'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(api.itemQueries.single.favoritesOnly, isTrue);
    expect(api.itemQueries.single.includeSortFields, isTrue);
  });

  testWidgets('lista vuota', (tester) async {
    await pumpList(tester, FakeLibraryApi());
    expect(find.text('La tua lista è vuota. Aggiungi film e serie con il cuore.'),
        findsOneWidget);
    expect(find.byType(CatalogFiltersBar), findsNothing);
  });

  testWidgets('barra dei filtri, conteggio e ordine per data di aggiunta',
      (tester) async {
    await pumpList(tester, apiWith(library()));
    expect(find.byType(CatalogFiltersBar), findsOneWidget);
    expect(find.text('3 titoli'), findsOneWidget);
    expect(xOf(tester, 'Dune'), lessThan(xOf(tester, 'Heat')));
    expect(xOf(tester, 'Heat'), lessThan(xOf(tester, 'Arrival')));
  });

  testWidgets('ordinamento per titolo', (tester) async {
    final api = await pumpList(tester, apiWith(library()));
    await tester.tap(find.text('Ordina per: Data di aggiunta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina per: Titolo').last);
    await tester.pumpAndSettle();
    expect(xOf(tester, 'Arrival'), lessThan(xOf(tester, 'Dune')));
    expect(xOf(tester, 'Dune'), lessThan(xOf(tester, 'Heat')));
    // Si ordina nell'app: nessuna nuova richiesta.
    expect(api.itemQueries, hasLength(1));
  });

  testWidgets('filtro per genere: griglia e conteggio', (tester) async {
    final api = await pumpList(tester, apiWith(library()));
    await tester.tap(find.text('Tutti i generi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crimine').last);
    await tester.pumpAndSettle();
    expect(find.text('1 titolo'), findsOneWidget);
    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    expect(api.itemQueries, hasLength(1));
  });

  testWidgets('"Visti" senza risultati e azzeramento', (tester) async {
    await pumpList(
        tester, apiWith([testItem(id: 'd', name: 'Dune', favorite: true)]));
    await tester.tap(find.text('Visti'));
    await tester.pumpAndSettle();
    expect(find.text('Nessun titolo con questi filtri.'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);

    await tester.tap(find.text('Azzera filtri').last);
    await tester.pumpAndSettle();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Nessun titolo con questi filtri.'), findsNothing);
  });

  // Griglia senza chiavi: togliendo Dune, la card di Heat ne riusa l'host.
  // L'anteprima di Dune non deve restare aperta su Heat.
  testWidgets('tolto dalla lista dall\'anteprima: l\'anteprima si chiude',
      (tester) async {
    final api = await pumpList(
        tester,
        FakeLibraryApi()
          ..onItems = (query, start, limit) => query.favoritesOnly
              ? pageOf([
                  testItem(id: 'm1', name: 'Dune', favorite: true),
                  testItem(id: 'm2', name: 'Heat', favorite: true),
                ])
              : pageOf([]));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Dune')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsOneWidget);

    await tester.tap(find.byTooltip('Rimuovi da La mia lista'));
    await tester.pumpAndSettle();
    expect(api.favoriteCalls, [('m1', false)]);
    expect(find.text('Dune'), findsNothing);
    expect(find.text('Heat'), findsOneWidget);
    expect(find.byType(CardPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
