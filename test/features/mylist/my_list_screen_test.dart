import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';

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
}
