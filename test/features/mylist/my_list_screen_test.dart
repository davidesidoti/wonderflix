import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';
import 'package:wonderflix/ui/card_preview.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  Future<FakeLibraryApi> pumpList(WidgetTester tester, FakeLibraryApi api) async {
    await pumpApp(tester, const MyListScreen(), overrides: [
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
    expect(find.text('LA MIA LISTA'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(api.itemQueries.single.favoritesOnly, isTrue);
  });

  testWidgets('lista vuota', (tester) async {
    await pumpList(tester, FakeLibraryApi());
    expect(find.text('La tua lista è vuota. Aggiungi film e serie con il cuore.'),
        findsOneWidget);
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
