import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

JellyfinItem ep(String id, String season, int seasonIndex, int index,
        {bool played = false, int position = 0, double? pct}) =>
    testItem(
      id: id,
      name: 'Episodio $index',
      kind: ItemKind.episode,
      seriesId: 's1',
      seriesName: 'The Last of Us',
      seasonId: season,
      seasonIndex: seasonIndex,
      index: index,
      runtimeMinutes: 45,
      played: played,
      positionTicks: position,
      playedPercentage: pct,
    );

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['s1'] =
          testItem(id: 's1', name: 'The Last of Us', kind: ItemKind.series, childCount: 2)
      ..seasonsBySeries['s1'] = [
        testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.season, index: 1),
        testItem(id: 'se2', name: 'Stagione 2', kind: ItemKind.season, index: 2),
      ]
      ..episodesBySeason['se1'] = [
        ep('e3', 'se1', 1, 3, played: true),
        ep('e4', 'se1', 1, 4, position: 13940000000, pct: 50),
      ]
      ..episodesBySeason['se2'] = [ep('e21', 'se2', 2, 1)]
      ..nextUpItems = [ep('e4', 'se1', 1, 4, position: 13940000000, pct: 50)];
  });

  Future<void> pumpSeries(WidgetTester tester,
      {String? seasonId, MotionLevel motion = MotionLevel.reduced}) async {
    await pumpApp(
        tester, Scaffold(body: ItemDetailScreen(itemId: 's1', seasonId: seasonId)),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
        motion: motion);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('prossimo episodio, stagioni ed episodi', (tester) async {
    await pumpSeries(tester);
    expect(find.text('THE LAST OF US'), findsOneWidget);
    expect(find.text('2024 · 2 stagioni'), findsOneWidget);
    expect(find.text('Riprendi S1:E4 · 23:14'), findsOneWidget);
    expect(find.text('Stagione 1'), findsOneWidget);
    expect(find.text('Stagione 2'), findsOneWidget);
    expect(find.text('3. Episodio 3'), findsOneWidget);
    expect(find.text('4. Episodio 4'), findsOneWidget);
    expect(api.nextUpCalls, contains('s1'));
  });

  testWidgets('cambio stagione', (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.text('Stagione 2'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1. Episodio 1'), findsOneWidget);
    expect(find.text('3. Episodio 3'), findsNothing);
  });

  testWidgets('la linea oro passa sotto la stagione scelta', (tester) async {
    await pumpSeries(tester);
    await tester.pumpAndSettle();
    final indicator = find.byKey(const Key('season-indicator'));
    expect(tester.getRect(indicator).left,
        closeTo(tester.getRect(find.text('Stagione 1')).left - 8, 1));
    await tester.tap(find.text('Stagione 2'));
    await tester.pumpAndSettle();
    expect(tester.getRect(indicator).left,
        closeTo(tester.getRect(find.text('Stagione 2')).left - 8, 1));
  });

  testWidgets('gli episodi entrano scaglionati solo cambiando stagione',
      (tester) async {
    await pumpSeries(tester, motion: MotionLevel.full);
    // Onda degli scheletri continua: niente pumpAndSettle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    StaggerGroup episodes(String seasonId) => tester.widget<StaggerGroup>(
        find.byKey(ValueKey('episodes-$seasonId')));
    // Alla prima apertura entrano con la scheda (elemento 5), non di nuovo.
    expect(episodes('se1').play, isFalse);

    await tester.tap(find.text('Stagione 2'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(episodes('se2').play, isTrue);
  });

  testWidgets('stagione iniziale da parametro', (tester) async {
    await pumpSeries(tester, seasonId: 'se2');
    expect(find.text('1. Episodio 1'), findsOneWidget);
  });

  testWidgets('nessun NextUp: propone il primo episodio', (tester) async {
    api.nextUpItems = [];
    await pumpSeries(tester);
    expect(find.text('Riproduci S1:E3'), findsOneWidget);
  });
}
