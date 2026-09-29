import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['m1'] = testItem(
        id: 'm1',
        name: 'Dune: Parte Due',
        overview: 'Paul Atreides si unisce ai Fremen.',
        positionTicks: 13940000000,
        playedPercentage: 20,
        people: [
          {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
          {'Id': 'p8', 'Name': 'Denis Villeneuve', 'Type': 'Director'},
        ],
        trailers: [
          {'Url': 'https://youtube.com/watch?v=x'},
        ],
      )
      ..similarItems = [testItem(id: 'm2', name: 'Arrival')];
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    // In app la schermata vive dentro lo Scaffold dell'AppShell (servono
    // Material e ScaffoldMessenger per IconButton e SnackBar).
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('titolo, trama, azioni, cast e simili', (tester) async {
    await pumpDetail(tester);
    expect(find.text('DUNE: PARTE DUE'), findsOneWidget);
    expect(find.text('Paul Atreides si unisce ai Fremen.'), findsOneWidget);
    expect(find.text('Riprendi da 23:14'), findsOneWidget);
    expect(find.text('Ricomincia'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    expect(find.text('Zendaya'), findsOneWidget);
    expect(find.text('Chani'), findsOneWidget);
    expect(find.text('Denis Villeneuve'), findsNothing,
        reason: 'il regista non è nel cast');
    expect(find.text('Simili'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
  });

  testWidgets('trailer con schema non web: nessun pulsante', (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1', trailers: [
      {'Url': 'javascript:alert(1)'},
    ]);
    await pumpDetail(tester);
    expect(find.text('DUNE: PARTE DUE'), findsOneWidget);
    expect(find.text('Trailer'), findsNothing);
  });

  testWidgets('cuore: aggiunge a La mia lista', (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byTooltip('Aggiungi a La mia lista'));
    await tester.pump();
    expect(api.favoriteCalls, [('m1', true)]);
    expect(find.byTooltip('Rimuovi da La mia lista'), findsOneWidget);
  });

  testWidgets('segna come visto', (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byTooltip('Segna come visto'));
    await tester.pump();
    expect(api.playedCalls, [('m1', true)]);
  });

  testWidgets('elemento inesistente: errore con riprova', (tester) async {
    api.itemsById.clear();
    await pumpDetail(tester);
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('solo trailer locale: pulsante presente', (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1', localTrailers: 1);
    await pumpDetail(tester);
    expect(find.text('Trailer'), findsOneWidget);
  });
}
