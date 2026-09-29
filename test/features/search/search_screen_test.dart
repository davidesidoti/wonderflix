import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/search/search_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  testWidgets('scrive, attende e mostra i risultati per sezione', (tester) async {
    final api = FakeLibraryApi()
      ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
          ? pageOf([testItem(id: 'm1', name: 'Dune')])
          : pageOf([]))
      ..people = [];
    await pumpApp(tester, const Scaffold(body: SearchScreen()), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);

    expect(find.text('Scrivi almeno 2 lettere per cercare.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Serie'), findsNothing);
  });

  testWidgets('nessun risultato', (tester) async {
    final api = FakeLibraryApi();
    await pumpApp(tester, const Scaffold(body: SearchScreen()), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Nessun risultato per "zzz"'), findsOneWidget);
  });
}
