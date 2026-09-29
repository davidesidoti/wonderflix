import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/person/person_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  testWidgets('biografia e filmografia sul server', (tester) async {
    final api = FakeLibraryApi()
      ..itemsById['p9'] = testItem(
          id: 'p9',
          name: 'Zendaya',
          kind: ItemKind.person,
          year: null,
          overview: 'Attrice statunitense.')
      ..onItems = (query, start, limit) => query.personId == 'p9'
          ? pageOf([testItem(id: 'm1', name: 'Dune'), testItem(id: 'm2', name: 'Challengers')])
          : pageOf([]);

    await pumpApp(tester, const Scaffold(body: PersonScreen(personId: 'p9')),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider
              .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
        ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('ZENDAYA'), findsOneWidget);
    expect(find.text('Attrice statunitense.'), findsOneWidget);
    expect(find.text('Su WonderFlix'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Challengers'), findsOneWidget);
    expect(api.itemQueries.last.kinds, {ItemKind.movie, ItemKind.series});
  });
}
