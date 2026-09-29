import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
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

  testWidgets('tacche dei capitoli (non quella all\'inizio)', (tester) async {
    final engine = FakeVideoEngine();
    await pumpApp(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(40),
          child: SeekBar(
            engine: engine,
            onSeek: (_) {},
            chapters: const [
              ChapterMark(start: Duration.zero, name: 'Inizio'),
              ChapterMark(start: Duration(minutes: 30), name: 'Arrakis'),
              ChapterMark(start: Duration(hours: 1), name: 'Deserto'),
            ],
          ),
        ),
      ),
    );
    final paint = tester.widget<CustomPaint>(find.byKey(const Key('chapter-ticks')));
    expect((paint.painter! as ChapterTicksPainter).fractions, [0.25, 0.5]);

    // Disegnate sopra la traccia, non sotto.
    final layers = tester
        .widget<Stack>(find.descendant(
            of: find.byType(SeekBar), matching: find.byType(Stack)).first)
        .children;
    int layerOf(Finder finder) => layers.indexWhere((layer) => find
        .descendant(of: find.byWidget(layer), matching: finder)
        .evaluate()
        .isNotEmpty);
    expect(layerOf(find.byKey(const Key('chapter-ticks'))),
        greaterThan(layerOf(find.byType(Slider))));
  });

  testWidgets('anteprima al passaggio del mouse: tempo, capitolo, immagine',
      (tester) async {
    final engine = FakeVideoEngine();
    final previews = <Duration>[];
    await pumpApp(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(40, 300, 40, 40),
          child: SeekBar(
            engine: engine,
            onSeek: (_) {},
            chapters: const [
              ChapterMark(start: Duration.zero, name: 'Inizio'),
              ChapterMark(start: Duration(minutes: 45), name: 'Arrakis'),
            ],
            preview: (position) {
              previews.add(position);
              return const SizedBox(
                  key: Key('preview-image'), width: 240, height: 135);
            },
          ),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SeekBar)));
    await tester.pump();
    expect(find.text('1:00:00 · Arrakis'), findsOneWidget);
    expect(find.byKey(const Key('preview-image')), findsOneWidget);
    expect(previews.last, const Duration(hours: 1));

    // A un quarto della traccia (che inizia dopo il margine dello Slider).
    final bar = tester.getRect(find.byType(SeekBar));
    final track = bar.width - 2 * SeekBar.trackInset;
    await gesture.moveTo(
        Offset(bar.left + SeekBar.trackInset + 0.25 * track, bar.center.dy));
    await tester.pump();
    expect(find.text('30:00 · Inizio'), findsOneWidget);
    expect(previews.last, const Duration(minutes: 30));

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(find.textContaining('· Inizio'), findsNothing);
  });

  test('chapterAt', () {
    const chapters = [
      ChapterMark(start: Duration.zero, name: 'A'),
      ChapterMark(start: Duration(minutes: 10), name: 'B'),
    ];
    expect(chapterAt(chapters, const Duration(minutes: 5))?.name, 'A');
    expect(chapterAt(chapters, const Duration(minutes: 10))?.name, 'B');
    expect(chapterAt(const [], Duration.zero), isNull);
  });
}
