import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/pause_screen.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  test('anno, durata e al massimo due generi; si omette ciò che manca', () {
    expect(
        pauseScreenMeta(testItem(
            year: 2024,
            runtimeMinutes: 166,
            genres: ['Fantascienza', 'Avventura', 'Dramma'])),
        '2024 · 2h 46m · Fantascienza · Avventura');
    expect(pauseScreenMeta(testItem(year: null, runtimeMinutes: null)), '');
  });

  Future<ValueNotifier<bool>> pumpPause(WidgetTester tester, JellyfinItem item,
      {bool visible = false, MotionLevel motion = MotionLevel.reduced}) async {
    final shown = ValueNotifier(visible);
    addTearDown(shown.dispose);
    await pumpApp(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, value, _) => PauseScreen(item: item, visible: value),
      ),
      motion: motion,
    );
    return shown;
  }

  testWidgets('nascosta non è nell\'albero; mostrata, tutti i dati',
      (tester) async {
    final shown = await pumpPause(
        tester,
        testItem(
          id: 'e4',
          name: 'Pilot',
          kind: ItemKind.episode,
          seriesName: 'Breaking Bad',
          index: 4,
          seasonIndex: 1,
          year: 2008,
          runtimeMinutes: 58,
          genres: ['Dramma'],
          overview: 'Un professore scopre di essere malato.',
        ));
    expect(find.byKey(const Key('pause-screen')), findsNothing);

    shown.value = true;
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);
    expect(find.text('BREAKING BAD'), findsOneWidget);
    expect(find.text('S1:E4 · Pilot'), findsOneWidget);
    expect(find.text('2008 · 58m · Dramma'), findsOneWidget);
    expect(find.text('Un professore scopre di essere malato.'), findsOneWidget);
    expect(find.text('In pausa'), findsOneWidget);

    shown.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pause-screen')), findsNothing);
  });

  testWidgets('animazioni complete: il testo sale entrando', (tester) async {
    final shown = await pumpPause(tester, testItem(name: 'Dune'),
        motion: MotionLevel.full);
    shown.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    double rise() => tester
        .widget<Transform>(find
            .ancestor(
                of: find.text('STAI GUARDANDO'),
                matching: find.byType(Transform))
            .first)
        .transform
        .getTranslation()
        .y;
    expect(rise(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(rise(), 0);
  });
}
