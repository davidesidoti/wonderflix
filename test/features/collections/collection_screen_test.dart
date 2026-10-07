import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collection_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

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
}
