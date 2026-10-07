import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collection_screen.dart';
import 'package:wonderflix/features/detail/detail_backdrop.dart';
import 'package:wonderflix/features/detail/detail_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/skeletons.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['c1'] = testItem(
          id: 'c1',
          name: 'Matrix - Collezione',
          kind: ItemKind.boxSet,
          year: null,
          runtimeMinutes: null,
          overview: 'Due realtà.')
      ..itemsByCollection['c1'] = [
        testItem(id: 'm1', name: 'Matrix', played: true),
        testItem(
            id: 'm2',
            name: 'Matrix Reloaded',
            positionTicks: 600000000,
            playedPercentage: 10),
        testItem(id: 'm3', name: 'Matrix Revolutions'),
      ];
  });

  Future<void> pumpCollection(WidgetTester tester) async {
    await pumpApp(
        tester, const Scaffold(body: CollectionScreen(collectionId: 'c1')),
        surfaceSize: const Size(1440, 1400),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ]);
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('testata, conteggio, sinossi e film in ordine', (tester) async {
    await pumpCollection(tester);
    expect(find.text('MATRIX - COLLEZIONE'), findsOneWidget);
    expect(find.text('3 film · 1 visto'), findsOneWidget);
    expect(find.text('Due realtà.'), findsOneWidget);
    expect(find.text('Matrix Revolutions'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Matrix')).dx,
        lessThan(tester.getTopLeft(find.text('Matrix Reloaded')).dx));
    expect(api.collectionItemsCalls, ['c1']);
  });

  testWidgets('pulsante: il primo film non visto, ripreso se iniziato',
      (tester) async {
    await pumpCollection(tester);
    expect(find.text('Riprendi "Matrix Reloaded"'), findsOneWidget);
  });

  testWidgets('tutti visti: si riparte dal primo', (tester) async {
    api.itemsByCollection['c1'] = [
      testItem(id: 'm1', name: 'Matrix', played: true),
      testItem(id: 'm2', name: 'Matrix Reloaded', played: true),
    ];
    await pumpCollection(tester);
    expect(find.text('Riproduci "Matrix"'), findsOneWidget);
    expect(find.text('2 film · 2 visti'), findsOneWidget);
  });

  testWidgets('nessuno visto: il primo', (tester) async {
    api.itemsByCollection['c1'] = [
      testItem(id: 'm1', name: 'Matrix'),
      testItem(id: 'm2', name: 'Matrix Reloaded'),
    ];
    await pumpCollection(tester);
    expect(find.text('Riproduci "Matrix"'), findsOneWidget);
    expect(find.text('2 film · 0 visti'), findsOneWidget);
  });

  testWidgets('saga che non c\'è: errore con Riprova', (tester) async {
    api.itemsById.clear();
    await pumpCollection(tester);
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('un errore sulla saga già letta lascia lo sfondo', (tester) async {
    await pumpCollection(tester);
    expect(find.byType(DetailBackdrop), findsOneWidget);

    api.itemsById.clear();
    ProviderScope.containerOf(tester.element(find.byType(CollectionScreen)))
        .invalidate(itemProvider('c1'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprova'), findsOneWidget);
    expect(find.byType(DetailBackdrop), findsOneWidget);
  });

  testWidgets('la testata arriva con i titoli, già con conteggio e pulsante',
      (tester) async {
    final gate = Completer<void>();
    api.collectionItemsGate = gate;
    await pumpCollection(tester);
    // La saga c'è e i titoli sono già partiti, ma non arrivati: lo
    // scheletro, senza una testata a metà.
    expect(api.collectionItemsCalls, ['c1']);
    expect(find.byType(DetailSkeleton), findsOneWidget);
    final title = find.text('MATRIX - COLLEZIONE');
    expect(title, findsNothing);

    gate.complete();
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      // In nessun fotogramma la testata c'è senza conteggio e pulsante.
      if (title.evaluate().isNotEmpty) {
        expect(find.text('3 film · 1 visto'), findsOneWidget);
        expect(find.text('Riprendi "Matrix Reloaded"'), findsOneWidget);
      }
    }
    expect(title, findsOneWidget);
    expect(find.text('Matrix Revolutions'), findsOneWidget);
  });

  testWidgets('titoli non letti: errore con Riprova nella pagina, e li ricarica',
      (tester) async {
    api.collectionItemsError = const ServerErrorException(500);
    await pumpCollection(tester);
    // La testata c'è (senza conteggio né pulsante) e l'errore sta sotto.
    expect(find.text('MATRIX - COLLEZIONE'), findsOneWidget);
    expect(find.text('Due realtà.'), findsOneWidget);
    expect(find.textContaining('film ·'), findsNothing);
    expect(find.textContaining('Riproduci'), findsNothing);
    expect(find.text('Riprova'), findsOneWidget);

    // Durante il nuovo tentativo, lo scheletro al posto dell'errore.
    api.collectionItemsError = null;
    final gate = Completer<void>();
    api.collectionItemsGate = gate;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprova'), findsNothing);
    expect(find.byType(PosterGridSkeleton), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprova'), findsNothing);
    expect(find.text('Matrix Revolutions'), findsOneWidget);
    expect(find.text('3 film · 1 visto'), findsOneWidget);
    expect(find.text('Riprendi "Matrix Reloaded"'), findsOneWidget);
  });
}
