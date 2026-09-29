import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() => api = FakeLibraryApi());

  Future<void> pumpHome(WidgetTester tester, {double height = 900}) async {
    await pumpApp(tester, const HomeScreen(), overrides: [
      libraryApiProvider.overrideWithValue(api),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    ]);
    // La lista è pigra: serve una finestra alta perché tutte le righe
    // (hero + 4 righe) siano costruite.
    await tester.binding.setSurfaceSize(Size(1440, height));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('mostra le righe con contenuti', (tester) async {
    api
      ..resumeItems = [testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)]
      ..onItems = (query, start, limit) => query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'The Bear', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')]);
    await pumpHome(tester, height: 1600);

    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
    expect(find.text('Serie aggiunte di recente'), findsOneWidget);
    expect(find.text('Oppenheimer'), findsWidgets);
    expect(find.text('Prossimi episodi'), findsNothing, reason: 'riga vuota nascosta');
  });

  testWidgets('libreria vuota', (tester) async {
    await pumpHome(tester);
    expect(find.text("Qui non c'è ancora niente."), findsOneWidget);
  });

  testWidgets('errore con riprova', (tester) async {
    api.error = const ServerUnreachableException();
    await pumpHome(tester);
    expect(find.text('Riprova'), findsOneWidget);

    api.error = null;
    api.onItems = (query, start, limit) => pageOf([testItem(id: 'm1', name: 'Dune')]);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
  });
}
