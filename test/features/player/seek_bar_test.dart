import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/seek_bar.dart';
import 'package:wonderflix/features/player/seek_segments.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  const chapters = [
    ChapterMark(start: Duration.zero, name: 'Inizio'),
    ChapterMark(start: Duration(hours: 1), name: 'Arrakis'),
  ];

  SeekBarPainter painter(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.byKey(const Key('seek-bar-paint'))).painter!
          as SeekBarPainter;

  /// Punto della traccia a [fraction] (la traccia inizia dopo il margine).
  Offset at(WidgetTester tester, double fraction) {
    final bar = tester.getRect(find.byType(SeekBar));
    final track = bar.width - 2 * SeekBar.trackInset;
    return Offset(bar.left + SeekBar.trackInset + fraction * track,
        bar.center.dy);
  }

  /// `Semantics` dello slider: `SeekBar` stesso non ha un nodo (il suo primo
  /// render object è il `LayoutBuilder`), quindi si cerca il `Semantics`.
  final sliderFinder = find.descendant(
    of: find.byType(SeekBar),
    matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.slider == true),
  );

  /// Lo stesso nodo cercato nell'albero semantico, per eseguirne le azioni.
  final sliderSemantics = find.semantics.byFlag(SemanticsFlag.isSlider);

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  Future<void> pumpBar(
    WidgetTester tester,
    FakeVideoEngine engine, {
    ValueChanged<Duration>? onSeek,
    List<ChapterMark> chapters = const [],
    List<SeekZone> zones = const [],
    Widget? Function(Duration)? preview,
    MotionLevel motion = MotionLevel.reduced,
  }) =>
      pumpApp(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(40, 300, 40, 40),
            child: Align(
              alignment: Alignment.topCenter,
              child: SeekBar(
                engine: engine,
                onSeek: onSeek ?? (_) {},
                chapters: chapters,
                zones: zones,
                preview: preview,
              ),
            ),
          ),
        ),
        motion: motion,
      );

  testWidgets('posizione, parte scaricata e salto con un clic', (tester) async {
    final engine = FakeVideoEngine();
    Duration? seeked;
    await pumpBar(tester, engine, onSeek: (p) => seeked = p);
    engine
      ..emitDuration(const Duration(hours: 2))
      ..emitPosition(const Duration(minutes: 30))
      ..emitBuffer(const Duration(minutes: 45));
    await tester.pump(); // consegna gli eventi degli stream
    await tester.pump();

    expect(painter(tester).duration, const Duration(hours: 2));
    expect(painter(tester).position, const Duration(minutes: 30));
    expect(painter(tester).buffer, const Duration(minutes: 45));

    await tester.tap(find.byType(SeekBar));
    await tester.pump();
    expect(seeked!.inSeconds, closeTo(3600, 5));
  });

  testWidgets('semantica da slider: aumenta e diminuisce di un passo, '
      'niente tap né scroll', (tester) async {
    final handle = tester.ensureSemantics();
    final engine = FakeVideoEngine();
    final seeks = <Duration>[];
    await pumpBar(tester, engine, onSeek: seeks.add);
    engine.emitPosition(const Duration(minutes: 30));
    await tester.pump(); // consegna gli eventi degli stream
    await tester.pump();

    expect(
      tester.getSemantics(sliderFinder),
      matchesSemantics(
        isSlider: true,
        value: '30:00',
        increasedValue: '30:10',
        decreasedValue: '29:50',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );

    tester.semantics.performAction(sliderSemantics, SemanticsAction.increase);
    await tester.pump();
    expect(seeks, [const Duration(minutes: 30, seconds: 10)]);

    tester.semantics.performAction(sliderSemantics, SemanticsAction.decrease);
    await tester.pump();
    expect(seeks, [
      const Duration(minutes: 30, seconds: 10),
      const Duration(minutes: 30),
    ]);
    handle.dispose();
  });

  testWidgets('semantica: il passo si ferma all\'inizio e alla fine',
      (tester) async {
    final handle = tester.ensureSemantics();
    final engine = FakeVideoEngine();
    final seeks = <Duration>[];
    await pumpBar(tester, engine, onSeek: seeks.add);

    engine.emitPosition(const Duration(seconds: 4));
    await tester.pump(); // consegna gli eventi degli stream
    await tester.pump();
    tester.semantics.performAction(sliderSemantics, SemanticsAction.decrease);
    await tester.pump();

    engine.emitPosition(const Duration(hours: 2) - const Duration(seconds: 4));
    await tester.pump();
    await tester.pump();
    tester.semantics.performAction(sliderSemantics, SemanticsAction.increase);
    await tester.pump();

    expect(seeks, [Duration.zero, const Duration(hours: 2)]);
    handle.dispose();
  });

  testWidgets('semantica: senza durata nota non ci sono azioni',
      (tester) async {
    final handle = tester.ensureSemantics();
    final engine = FakeVideoEngine();
    await pumpBar(tester, engine);
    engine.emitDuration(Duration.zero);
    await tester.pump(); // consegna gli eventi degli stream
    await tester.pump();

    expect(
      tester.getSemantics(sliderFinder),
      matchesSemantics(isSlider: true, value: '00:00'),
    );
    handle.dispose();
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

  testWidgets('un tratto per capitolo, le zone passano al disegno',
      (tester) async {
    const zones = [
      SeekZone(SeekZoneKind.intro, Duration(minutes: 1), Duration(minutes: 2)),
    ];
    await pumpBar(tester, FakeVideoEngine(), chapters: const [
      ChapterMark(start: Duration.zero, name: 'Inizio'),
      ChapterMark(start: Duration(minutes: 30), name: 'Arrakis'),
      ChapterMark(start: Duration(hours: 1), name: 'Deserto'),
    ], zones: zones);
    expect(painter(tester).segments, const [
      SeekSegment(Duration.zero, Duration(minutes: 30)),
      SeekSegment(Duration(minutes: 30), Duration(hours: 1)),
      SeekSegment(Duration(hours: 1), Duration(hours: 2)),
    ]);
    expect(painter(tester).zones, zones);
  });

  testWidgets('anteprima al passaggio del mouse: tempo, capitolo, immagine',
      (tester) async {
    final previews = <Duration>[];
    await pumpBar(tester, FakeVideoEngine(), chapters: chapters,
        preview: (position) {
      previews.add(position);
      return const SizedBox(key: Key('preview-image'), width: 240, height: 135);
    });
    final gesture = await mouse(tester);
    await gesture.moveTo(at(tester, 0.5));
    await tester.pump();
    expect(find.text('1:00:00 · Arrakis'), findsOneWidget);
    expect(find.byKey(const Key('preview-image')), findsOneWidget);
    expect(previews.last, const Duration(hours: 1));

    await gesture.moveTo(at(tester, 0.25));
    await tester.pump();
    expect(find.text('30:00 · Inizio'), findsOneWidget);
    expect(previews.last, const Duration(minutes: 30));

    // L'anteprima sfuma; finita la dissolvenza esce dall'albero.
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.textContaining('· Inizio'), findsNothing);
  });

  testWidgets('anteprima in una zona: etichetta oro con il nome',
      (tester) async {
    await pumpBar(tester, FakeVideoEngine(), chapters: chapters, zones: const [
      SeekZone(SeekZoneKind.outro, Duration(minutes: 90), Duration(hours: 2)),
    ]);
    final gesture = await mouse(tester);
    await gesture.moveTo(at(tester, 0.25));
    await tester.pump();
    expect(find.byKey(const Key('seek-zone-tag')), findsNothing);

    await gesture.moveTo(at(tester, 0.9));
    await tester.pump();
    expect(find.byKey(const Key('seek-zone-tag')), findsOneWidget);
    expect(find.text('Titoli di coda'), findsOneWidget);
  });

  testWidgets('mouse sopra: barra più alta, tratto sotto il mouse di più, '
      'cursore', (tester) async {
    await pumpBar(tester, FakeVideoEngine(),
        chapters: chapters, motion: MotionLevel.full);
    expect(painter(tester).hover, 0);
    expect(painter(tester).thumb, 0);

    final gesture = await mouse(tester);
    await gesture.moveTo(at(tester, 0.25));
    await tester.pump();
    await tester.pump(WfMotion.fast);
    expect(painter(tester).hover, 1);
    expect(painter(tester).hoveredSegment, 0);
    expect(painter(tester).emphasis, 1);
    expect(painter(tester).thumb, closeTo(1, 0.001));

    await gesture.moveTo(at(tester, 0.75));
    await tester.pump();
    expect(painter(tester).hoveredSegment, 1);

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(WfMotion.fast);
    expect(painter(tester).hover, 0);
    expect(painter(tester).hoveredSegment, isNull);
    expect(painter(tester).thumb, closeTo(0, 0.001));
    await tester.pumpAndSettle();
  });

  testWidgets('trascinamento: l\'anteprima segue, un solo salto alla fine',
      (tester) async {
    final seeks = <Duration>[];
    await pumpBar(tester, FakeVideoEngine(),
        onSeek: seeks.add,
        chapters: chapters,
        preview: (_) => const SizedBox(key: Key('preview-image'), width: 240));
    final gesture = await tester.startGesture(at(tester, 0.25));
    await gesture.moveTo(at(tester, 0.4));
    await tester.pump();
    expect(find.byKey(const Key('preview-image')), findsOneWidget);
    expect(seeks, isEmpty);
    expect(painter(tester).position.inMinutes, closeTo(48, 1),
        reason: 'durante il trascinamento la barra segue il dito');

    await gesture.moveTo(at(tester, 0.5));
    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single.inSeconds, closeTo(3600, 5));
    await tester.pumpAndSettle();
  });

  test('chapterAt', () {
    const marks = [
      ChapterMark(start: Duration.zero, name: 'A'),
      ChapterMark(start: Duration(minutes: 10), name: 'B'),
    ];
    expect(chapterAt(marks, const Duration(minutes: 5))?.name, 'A');
    expect(chapterAt(marks, const Duration(minutes: 10))?.name, 'B');
    expect(chapterAt(const [], Duration.zero), isNull);
  });
}
