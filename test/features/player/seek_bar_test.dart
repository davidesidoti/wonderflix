import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/seek_bar.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('posizione, parte scaricata e salto con un clic', (tester) async {
    final engine = FakeVideoEngine();
    Duration? seeked;
    await pumpApp(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(40),
          child: SeekBar(engine: engine, onSeek: (p) => seeked = p),
        ),
      ),
    );
    engine
      ..emitDuration(const Duration(hours: 2))
      ..emitPosition(const Duration(minutes: 30))
      ..emitBuffer(const Duration(minutes: 45));
    await tester.pump(); // consegna gli eventi degli stream
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 7200);
    expect(slider.value, 1800);
    expect(slider.secondaryTrackValue, 2700);

    await tester.tap(find.byType(Slider));
    await tester.pump();
    expect(seeked!.inSeconds, closeTo(3600, 5));
  });

  testWidgets('tempo trascorso e totale', (tester) async {
    final engine = FakeVideoEngine();
    await pumpApp(tester, Scaffold(body: TimeLabel(engine: engine)));
    engine
      ..emitDuration(const Duration(hours: 1, minutes: 45))
      ..emitPosition(const Duration(minutes: 12, seconds: 3));
    await tester.pump(); // consegna gli eventi degli stream
    await tester.pump();
    expect(find.text('12:03 / 1:45:00'), findsOneWidget);
  });
}
