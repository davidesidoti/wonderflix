import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/card_preview.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  Future<List<String>> pumpPreview(WidgetTester tester, JellyfinItem item,
      {FakeLibraryApi? api}) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Center(
        child: SizedBox(
          width: 360,
          height: 360 * 9 / 16 + previewBodyHeight,
          child: CardPreview(
            item: item,
            heroTag: null,
            onPlay: () => calls.add('play'),
            onDetails: () => calls.add('details'),
          ),
        ),
      ),
      overrides: [
        signedIn,
        libraryApiProvider.overrideWithValue(api ?? FakeLibraryApi()),
      ],
    );
    return calls;
  }

  testWidgets('film: titolo, dati, generi, pulsanti', (tester) async {
    final calls = await pumpPreview(tester, testItem(id: 'm1'));
    expect(find.text('DUNE: PARTE DUE'), findsOneWidget);
    expect(find.textContaining('2024'), findsWidgets);
    expect(find.byTooltip('Riproduci'), findsOneWidget);
    expect(find.byTooltip('Aggiungi a La mia lista'), findsOneWidget);
    expect(find.byTooltip('Segna come visto'), findsOneWidget);
    await tester.tap(find.byTooltip('Riproduci'));
    await tester.tap(find.byTooltip('Dettagli'));
    expect(calls, ['play', 'details']);
  });

  testWidgets('iniziato: "Riprendi" e barra dell\'avanzamento', (tester) async {
    await pumpPreview(tester, testItem(id: 'm1', playedPercentage: 40));
    expect(find.byTooltip('Riprendi'), findsOneWidget);
    expect(find.byKey(const Key('preview-progress')), findsOneWidget);
  });

  testWidgets('episodio: titolo della serie, codice, niente cuore',
      (tester) async {
    await pumpPreview(
      tester,
      testItem(
        id: 'e4',
        name: 'Please Hold',
        kind: ItemKind.episode,
        seriesName: 'The Last of Us',
        index: 4,
        seasonIndex: 1,
      ),
    );
    expect(find.text('THE LAST OF US'), findsOneWidget);
    expect(find.text('S1:E4 · Please Hold'), findsOneWidget);
    expect(find.byTooltip('Aggiungi a La mia lista'), findsNothing);
    expect(find.byTooltip('Segna come visto'), findsOneWidget);
  });

  testWidgets('clic sull\'immagine: come "Dettagli"', (tester) async {
    final calls = await pumpPreview(tester, testItem(id: 'm1'));
    await tester.tap(find.byKey(const Key('preview-image')));
    expect(calls, ['details']);
  });

  testWidgets('cuore: aggiunge a La mia lista', (tester) async {
    final api = FakeLibraryApi();
    await pumpPreview(tester, testItem(id: 'm1'), api: api);
    await tester.tap(find.byTooltip('Aggiungi a La mia lista'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Rimuovi da La mia lista'), findsOneWidget);
    expect(find.byIcon(LucideIcons.heart), findsOneWidget);
  });

  testWidgets('tutti i dati: entrano nell\'altezza del corpo', (tester) async {
    // Il caso più lungo: episodio (riga in più) con voto, classificazione,
    // generi e avanzamento. Un overflow farebbe fallire il test.
    await pumpPreview(
      tester,
      JellyfinItem.fromJson({
        'Id': 'e4',
        'Name': 'Please Hold',
        'Type': 'Episode',
        'SeriesName': 'The Last of Us',
        'IndexNumber': 4,
        'ParentIndexNumber': 1,
        'ProductionYear': 2023,
        'RunTimeTicks': 45 * 600000000,
        'CommunityRating': 8.7,
        'OfficialRating': 'VM14',
        'Genres': ['Dramma', 'Fantascienza', 'Azione', 'Avventura'],
        'UserData': {'PlayedPercentage': 40},
      }),
    );
    expect(find.text('Dramma · Fantascienza · Azione'), findsOneWidget);
    expect(find.byKey(const Key('preview-progress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
