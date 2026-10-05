import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeRequestsApi requests;

  setUp(() {
    library = FakeLibraryApi()
      ..itemsById['s1'] = testItem(
          id: 's1',
          name: 'The Last of Us',
          kind: ItemKind.series,
          childCount: 1,
          tmdbId: 100088)
      ..seasonsBySeries['s1'] = [
        testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.season, index: 1),
      ];
    requests = FakeRequestsApi()
      ..titles[100088] = testDetails(
        tmdbId: 100088,
        title: 'The Last of Us',
        type: RequestMediaType.tv,
        status: TitleStatus.partial,
        seasons: const [
          SeasonInfo(seasonNumber: 1, episodeCount: 9, status: TitleStatus.available),
          SeasonInfo(seasonNumber: 2, episodeCount: 7),
          SeasonInfo(seasonNumber: 3, episodeCount: 8),
        ],
      );
  });

  Future<void> pumpSeries(WidgetTester tester, {bool available = true}) async {
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 's1')),
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        ...requestsTestOverrides(requests, available: available),
      ],
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('stagioni mancanti: "Richiedi stagioni" apre la scelta e chiede',
      (tester) async {
    await pumpSeries(tester);
    expect(find.text('Richiedi stagioni'), findsOneWidget);

    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(find.descendant(of: dialog, matching: find.text('The Last of Us')), findsOneWidget);
    expect(find.text('Stagione 2 · 7 episodi'), findsOneWidget);

    await tester.tap(find.text('Stagione 3 · 8 episodi'));
    await tester.pump();
    await tester.tap(find.text('Richiedi 1 stagione'));
    await tester.pumpAndSettle();

    expect(requests.created.single.seasons, [2]);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Richiesta inviata'), findsOneWidget);
  });

  testWidgets('nessuna stagione da chiedere: niente pulsante', (tester) async {
    requests.titles[100088] = testDetails(
      tmdbId: 100088,
      type: RequestMediaType.tv,
      status: TitleStatus.available,
      seasons: const [
        SeasonInfo(seasonNumber: 1, episodeCount: 9, status: TitleStatus.available),
      ],
    );
    await pumpSeries(tester);

    expect(find.text('Richiedi stagioni'), findsNothing);
  });

  testWidgets('senza la funzione: niente pulsante e niente Seerr', (tester) async {
    await pumpSeries(tester, available: false);

    expect(find.text('Richiedi stagioni'), findsNothing);
    expect(requests.calls, isEmpty);
  });

  testWidgets('chi non può chiedere non vede il pulsante', (tester) async {
    requests.meValue =
        const RequestsMe(canRequest: false, canManage: false, hasAccount: true);
    await pumpSeries(tester);

    expect(find.text('Richiedi stagioni'), findsNothing);
    expect(requests.calls.where((c) => c.startsWith('title:')), isEmpty);
  });

  testWidgets('Invio chiede subito: "Richiedi" ha il fuoco all\'apertura',
      (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Le stagioni da chiedere sono tutte scelte all'apertura.
    expect(requests.created.single.seasons, [2, 3]);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('un nome lungo sta su una riga con i puntini', (tester) async {
    const long = 'Un titolo di serie molto più lungo di quanto la finestra '
        'possa mostrare in una riga sola, con tutti i suoi sottotitoli';
    library.itemsById['s1'] = testItem(
        id: 's1',
        name: long,
        kind: ItemKind.series,
        childCount: 1,
        tmdbId: 100088);
    await pumpSeries(tester);
    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();

    final name = tester.widget<Text>(find.descendant(
        of: find.byType(Dialog), matching: find.text(long)));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
  });

  testWidgets('la finestra ha il suo titolo come nome per lo screen reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpSeries(tester);
    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((w) =>
          w is Semantics &&
          w.properties.namesRoute == true &&
          w.properties.scopesRoute == true &&
          w.properties.label == 'Richiedi stagioni'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
