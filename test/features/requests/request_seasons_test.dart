import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
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

  Future<void> pumpSeries(WidgetTester tester,
      {bool available = true, String itemId = 's1'}) async {
    await pumpApp(
      tester,
      Scaffold(body: ItemDetailScreen(itemId: itemId)),
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

  testWidgets('durante l\'invio la finestra non si chiude: né Esc né Annulla',
      (tester) async {
    final gate = requests.createGate = Completer<void>();
    await pumpSeries(tester);
    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Richiedi'));
    await tester.pump();
    expect(requests.created.single.seasons, [2, 3]);

    // La richiesta è in viaggio: la finestra resta, e non perde l'avviso.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    // Il clic sul velo, fuori dalla finestra.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Richiesta inviata'), findsOneWidget);
  });

  testWidgets('Annulla: nessuna richiesta e nessun avviso', (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(requests.created, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Annulla scarta le caselle tolte: riaprendo ci sono tutte',
      (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stagione 3 · 8 episodi'));
    await tester.pump();
    expect(find.text('Richiedi 1 stagione'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    // La scelta sta nel controller della scheda, che la testata tiene vivo:
    // senza un ritorno alla scelta di partenza Invio chiederebbe solo la 2.
    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();
    expect(find.text('Richiedi 1 stagione'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(requests.created.single.seasons, [2, 3]);
  });

  testWidgets('errore di Seerr sulla scheda: niente pulsante e niente avviso',
      (tester) async {
    // `title` lancia `invalid` per un id che il finto non conosce.
    requests.titles.remove(100088);
    await pumpSeries(tester);

    expect(requests.calls, contains('title:tv:100088'));
    expect(find.byType(DetailHeader), findsOneWidget);
    expect(find.text('Richiedi stagioni'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('chieste le ultime stagioni: il pulsante sparisce', (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.text('Richiedi stagioni'));
    await tester.pumpAndSettle();

    // Dopo la richiesta Seerr non ha più stagioni da chiedere.
    requests.titles[100088] = testDetails(
      tmdbId: 100088,
      title: 'The Last of Us',
      type: RequestMediaType.tv,
      status: TitleStatus.processing,
      seasons: const [
        SeasonInfo(seasonNumber: 1, episodeCount: 9, status: TitleStatus.available),
        SeasonInfo(seasonNumber: 2, episodeCount: 7, status: TitleStatus.pending),
        SeasonInfo(seasonNumber: 3, episodeCount: 8, status: TitleStatus.pending),
      ],
    );
    await tester.tap(find.text('Richiedi'));
    await tester.pumpAndSettle();

    expect(requests.created.single.seasons, [2, 3]);
    expect(find.text('Richiesta inviata'), findsOneWidget);
    expect(find.text('Richiedi stagioni'), findsNothing);
  });

  testWidgets('un film con l\'id TMDB non tocca la scheda di Seerr', (tester) async {
    library.itemsById['m1'] = testItem(id: 'm1', tmdbId: 438631);
    await pumpSeries(tester, itemId: 'm1');

    expect(find.byType(DetailHeader), findsOneWidget);
    expect(find.text('Richiedi stagioni'), findsNothing);
    expect(requests.calls.where((c) => c.startsWith('title:')), isEmpty);
  });

  testWidgets('"Richiedi stagioni" arriva dopo i toggle e non li sposta',
      (tester) async {
    // La scheda di Seerr arriva tardi: il pulsante compare dopo gli altri.
    final gate = requests.titleGate = Completer<void>();
    await pumpSeries(tester);
    Finder inHeader(IconData icon) =>
        find.descendant(of: find.byType(DetailHeader), matching: find.byIcon(icon));
    expect(find.text('Richiedi stagioni'), findsNothing);
    final heart = tester.getCenter(inHeader(LucideIcons.heart));
    final check = tester.getCenter(inHeader(LucideIcons.check));

    gate.complete();
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(find.text('Richiedi stagioni'), findsOneWidget);
    expect(tester.getCenter(inHeader(LucideIcons.heart)), heart);
    expect(tester.getCenter(inHeader(LucideIcons.check)), check);
    expect(tester.getCenter(find.text('Richiedi stagioni')).dx, greaterThan(check.dx));
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
