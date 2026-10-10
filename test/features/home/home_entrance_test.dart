import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/ui/media_row.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..resumeItems = [testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)]
      ..onItems = (query, start, limit) => query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'The Bear', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')]);
  });

  /// Le risposte finte arrivano in pochi fotogrammi: composizione, poi
  /// righe.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  testWidgets('prima volta: le righe entrano scaglionate', (tester) async {
    await pumpApp(tester, const HomeScreen(),
        overrides: homeOverrides(library: api), motion: MotionLevel.full);
    await settle(tester);
    expect(find.byType(StaggerGroup), findsWidgets);
    final rows = tester.widget<StaggerGroup>(find.byKey(const Key('home-rows')));
    expect(rows.play, isTrue);
    // Le card della prima riga volano dentro con la riga.
    final card = tester.widget<Transform>(find
        .ancestor(of: find.text('Oppenheimer'), matching: find.byType(Transform))
        .first);
    expect(card.transform.getTranslation().x, greaterThan(0));
    await tester.pump(const Duration(seconds: 2));
  });

  // La "sessione" è il ProviderScope: togliere e rimettere la Home nello
  // stesso scope è come cambiare voce nella barra e tornare.
  testWidgets('seconda volta nella stessa sessione: nessuna entrata',
      (tester) async {
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pumpApp(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, value, _) =>
            value ? const HomeScreen() : const SizedBox(),
      ),
      overrides: homeOverrides(library: api),
      motion: MotionLevel.full,
    );
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    // Via e di nuovo (come cambiare voce e tornare alla Home).
    shown.value = false;
    await tester.pump();
    shown.value = true;
    await settle(tester);
    final rows = tester.widget<StaggerGroup>(find.byKey(const Key('home-rows')));
    expect(rows.play, isFalse);
    // Nemmeno le card delle righe volano dentro: nessun gruppo nelle righe.
    expect(find.byType(StaggerGroup), findsOneWidget);
  });

  testWidgets('una riga ricostruita scorrendo non rifà volare le card',
      (tester) async {
    // Una Home lunga: in fondo la prima riga esce dalla cache e si smonta.
    api
      ..resumeItems = [
        for (var i = 0; i < 6; i++)
          testItem(id: 'r$i', name: 'Ripresa $i', playedPercentage: 30),
      ]
      ..nextUpItems = [
        for (var i = 0; i < 6; i++)
          testItem(id: 'e$i', name: 'Episodio $i', kind: ItemKind.episode),
      ];
    await pumpApp(tester, const HomeScreen(),
        overrides: homeOverrides(library: api), motion: MotionLevel.full);
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Ripresa 0'), findsNothing,
        reason: 'la prima riga deve essere smontata');
    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 60));
    final firstRow = find.byType(MediaRow).first;
    expect(find.descendant(of: firstRow, matching: find.text('Ripresa 0')),
        findsOneWidget);
    for (final opacity in tester.widgetList<Opacity>(
        find.descendant(of: firstRow, matching: find.byType(Opacity)))) {
      expect(opacity.opacity, 1);
    }
    await tester.pump(const Duration(seconds: 2));
  });
}
