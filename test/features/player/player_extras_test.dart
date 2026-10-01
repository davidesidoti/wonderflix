import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_extras.dart';

import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('PositionSelector ricostruisce solo quando cambia il valore',
      (tester) async {
    final engine = FakeVideoEngine();
    var builds = 0;
    await pumpApp(
      tester,
      PositionSelector<bool>(
        engine: engine,
        select: (position) => position >= const Duration(minutes: 1),
        builder: (context, after) {
          builds++;
          return Text(after ? 'dopo' : 'prima');
        },
      ),
    );
    expect(find.text('prima'), findsOneWidget);
    final initial = builds;
    engine.emitPosition(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump();
    expect(builds, initial, reason: 'valore invariato');
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();
    await tester.pump();
    expect(find.text('dopo'), findsOneWidget);
    expect(builds, initial + 1);
  });

  final episode = testItem(
      id: 'e5',
      name: 'Cat in the Bag',
      kind: ItemKind.episode,
      seriesName: 'Breaking Bad',
      index: 5,
      seasonIndex: 1);

  testWidgets('pulsante: conto alla rovescia di 10 s, poi riproduce',
      (tester) async {
    var played = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: PlayNowButton(countdown: true, onPressed: () => played++),
        ),
      ),
    );
    expect(find.text('Riproduci ora · 10'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Riproduci ora · 9'), findsOneWidget);
    final fill = tester.widget<AnimatedFractionallySizedBox>(
        find.byType(AnimatedFractionallySizedBox));
    expect(fill.widthFactor, closeTo(0.1, 0.001));
    await tester.pump(const Duration(seconds: 9));
    expect(played, 1);
  });

  testWidgets('pulsante: in pausa il conto si ferma', (tester) async {
    var played = 0;
    final paused = ValueNotifier(false);
    addTearDown(paused.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: paused,
            builder: (context, value, _) => PlayNowButton(
                countdown: true, paused: value, onPressed: () => played++),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Riproduci ora · 7'), findsOneWidget);
    paused.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Riproduci ora · 7'), findsOneWidget);
    expect(played, 0);
    paused.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Riproduci ora · 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(played, 1);
  });

  testWidgets('pulsante senza conto alla rovescia', (tester) async {
    var played = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: PlayNowButton(countdown: false, onPressed: () => played++),
        ),
      ),
    );
    expect(find.text('Riproduci ora'), findsOneWidget);
    expect(find.byType(AnimatedFractionallySizedBox), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(played, 0);
    await tester.tap(find.text('Riproduci ora'));
    expect(played, 1);
  });

  testWidgets('scheda: episodio, pulsanti, entra da destra', (tester) async {
    var played = 0;
    var cancelled = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: NextEpisodeCard(
            episode: episode,
            countdown: false,
            onPlay: () => played++,
            onCancel: () => cancelled++,
          ),
        ),
      ),
      motion: MotionLevel.full,
    );
    double shift() => tester
        .widget<Transform>(find
            .ancestor(
                of: find.text('PROSSIMO EPISODIO'),
                matching: find.byType(Transform))
            .first)
        .transform
        .getTranslation()
        .x;
    await tester.pump(const Duration(milliseconds: 50));
    expect(shift(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(shift(), 0);
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    await tester.tap(find.text('Riproduci ora'));
    await tester.tap(find.text('Annulla'));
    expect((played, cancelled), (1, 1));
  });
}
