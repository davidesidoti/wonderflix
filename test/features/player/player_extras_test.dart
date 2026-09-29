import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('scheda: conto alla rovescia di 10 s, poi riproduce',
      (tester) async {
    var played = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: NextEpisodeCard(
            episode: episode,
            countdown: true,
            onPlay: () => played++,
            onCancel: () {},
          ),
        ),
      ),
    );
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    expect(find.text('Inizia tra 10 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Inizia tra 9 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(played, 1);
  });

  testWidgets('scheda senza conto alla rovescia: solo i pulsanti',
      (tester) async {
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
    );
    expect(find.textContaining('Inizia tra'), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(played, 0);
    await tester.tap(find.text('Riproduci ora'));
    await tester.tap(find.text('Annulla'));
    expect(played, 1);
    expect(cancelled, 1);
  });
}
