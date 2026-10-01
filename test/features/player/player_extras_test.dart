import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

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

  const fillKey = Key('play-now-fill');
  double fillOf(WidgetTester tester) =>
      tester.widget<FractionallySizedBox>(find.byKey(fillKey)).widthFactor!;

  /// Fotogrammi ogni 100 ms per [duration], come un'animazione vera.
  Future<void> frames(WidgetTester tester, Duration duration) async {
    for (var i = 0; i < duration.inMilliseconds ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Legge i pixel disegnati sotto [boundary] (coordinate globali).
  Future<Color Function(Offset)> snapshot(
      WidgetTester tester, Finder boundary) async {
    final render = tester.renderObject<RenderRepaintBoundary>(boundary);
    final image = (await tester.runAsync(render.toImage))!;
    addTearDown(image.dispose);
    final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    return (position) {
      final local = render.globalToLocal(position);
      final i = (local.dy.floor() * image.width + local.dx.floor()) * 4;
      return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
          bytes.getUint8(i + 1), bytes.getUint8(i + 2));
    };
  }

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
    expect(fillOf(tester), closeTo(0.1, 0.001));
    await tester.pump(const Duration(seconds: 9));
    expect(played, 1);
  });

  testWidgets('pulsante, animazioni complete: il fondo è pieno allo scatto',
      (tester) async {
    var played = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: PlayNowButton(countdown: true, onPressed: () => played++),
        ),
      ),
      motion: MotionLevel.full,
    );
    await frames(tester, const Duration(milliseconds: 500));
    expect(fillOf(tester), closeTo(0.05, 0.005),
        reason: 'il primo passo parte subito');
    await frames(tester, const Duration(milliseconds: 500));
    expect(find.text('Riproduci ora · 9'), findsOneWidget);
    expect(fillOf(tester), closeTo(0.1, 0.005));
    await frames(tester, const Duration(milliseconds: 8500));
    expect(fillOf(tester), closeTo(0.95, 0.005),
        reason: 'ogni passo finisce con il secondo che scatta');
    expect(played, 0);
    await frames(tester, const Duration(milliseconds: 500));
    expect(played, 1);
    expect(fillOf(tester), 1);
  });

  testWidgets('pulsante, animazioni complete: in pausa il fondo si ferma',
      (tester) async {
    final paused = ValueNotifier(false);
    addTearDown(paused.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: paused,
            builder: (context, value, _) =>
                PlayNowButton(countdown: true, paused: value, onPressed: () {}),
          ),
        ),
      ),
      motion: MotionLevel.full,
    );
    await frames(tester, const Duration(milliseconds: 3500));
    expect(find.text('Riproduci ora · 7'), findsOneWidget);
    paused.value = true;
    await frames(tester, const Duration(seconds: 2));
    expect(fillOf(tester), closeTo(0.3, 0.001),
        reason: "sull'ultimo secondo compiuto");
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'fermo non chiede fotogrammi');
    expect(find.text('Riproduci ora · 7'), findsOneWidget);
  });

  testWidgets('pulsante: un solo nodo con etichetta e tocco', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: PlayNowButton(countdown: true, onPressed: () {}),
        ),
      ),
    );
    expect(
        tester.getSemantics(find.byType(PlayNowButton)),
        isSemantics(
            label: 'Riproduci ora · 10', isButton: true, hasTapAction: true));
  });

  testWidgets('pulsante: la larghezza non cambia da "· 10" a "· 9"',
      (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: PlayNowButton(countdown: true, onPressed: () {}),
        ),
      ),
    );
    final before = tester.getSize(find.byType(PlayNowButton));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Riproduci ora · 9'), findsOneWidget);
    expect(tester.getSize(find.byType(PlayNowButton)), before);
  });

  testWidgets('pulsante: alto quanto WfButton nella stessa riga',
      (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: Wrap(
            spacing: 8,
            children: [
              PlayNowButton(countdown: true, onPressed: () {}),
              WfButton.secondary(
                  label: 'Annulla', icon: LucideIcons.x, onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    final play = tester.getSize(find.byType(PlayNowButton)).height;
    expect(play, 36, reason: 'densità compatta di Windows');
    expect(play, tester.getSize(find.byType(WfButton)).height);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets("pulsante: etichetta crema sul fondo vuoto, scura sull'oro",
      (tester) async {
    const shot = Key('shot');
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: shot,
            child: PlayNowButton(countdown: true, onPressed: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    final split = tester.getRect(find.byKey(fillKey)).right;
    final text = tester.getRect(find.text('Riproduci ora · 7'));
    expect(split, inExclusiveRange(text.left, text.right));
    final pixel = await snapshot(tester, find.byKey(shot));
    final filled = <double>[];
    final empty = <double>[];
    for (var x = text.left.ceil(); x < text.right; x++) {
      // Il bordo del fondo è sfumato: si salta.
      if ((x - split).abs() < 2) continue;
      final luminance =
          pixel(Offset(x + 0.5, text.center.dy)).computeLuminance();
      (x < split ? filled : empty).add(luminance);
    }
    // Crema ~0,82, oro ~0,42, fondo scuro sotto 0,06.
    expect(filled.where((l) => l > 0.6), isEmpty,
        reason: "sull'oro niente crema");
    expect(filled.where((l) => l < 0.05), isNotEmpty,
        reason: "sull'oro l'etichetta è scura");
    expect(empty.where((l) => l > 0.6), isNotEmpty,
        reason: "sul fondo vuoto l'etichetta è crema");
  });

  testWidgets('pulsante: passaggio del mouse visibile sopra il fondo oro',
      (tester) async {
    const shot = Key('shot');
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: shot,
            child: PlayNowButton(countdown: true, onPressed: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    // Sul fondo già pieno, prima dell'icona.
    final button = tester.getRect(find.byType(PlayNowButton));
    final spot = Offset(button.left + 5, button.center.dy);
    expect(tester.getRect(find.byKey(fillKey)).right,
        greaterThan(spot.dx + 2));
    final before = (await snapshot(tester, find.byKey(shot)))(spot);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(PlayNowButton)));
    await tester.pump();
    await tester.pump(WfMotion.medium);
    final after = (await snapshot(tester, find.byKey(shot)))(spot);
    expect(after.computeLuminance(),
        lessThan(before.computeLuminance() - 0.02),
        reason: 'il velo del passaggio sta sopra il riempimento');
    final glow = tester.widget<AnimatedContainer>(find.descendant(
        of: find.byType(PlayNowButton),
        matching: find.byKey(const Key('wf-button-glow'))));
    expect((glow.decoration! as BoxDecoration).boxShadow, isNotEmpty);
  });

  testWidgets('pulsante: il conto parte anche se arriva dopo',
      (tester) async {
    var played = 0;
    final countdown = ValueNotifier(false);
    addTearDown(countdown.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: countdown,
            builder: (context, value, _) =>
                PlayNowButton(countdown: value, onPressed: () => played++),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Riproduci ora'), findsOneWidget);
    countdown.value = true;
    await tester.pump();
    expect(find.text('Riproduci ora · 10'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Riproduci ora · 1'), findsOneWidget);
    expect(played, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(played, 1);
  });

  testWidgets('pulsante: tolto il conto il timer si ferma, poi riparte',
      (tester) async {
    var played = 0;
    final countdown = ValueNotifier(true);
    addTearDown(countdown.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: countdown,
            builder: (context, value, _) =>
                PlayNowButton(countdown: value, onPressed: () => played++),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Riproduci ora · 7'), findsOneWidget);
    countdown.value = false;
    await tester.pump();
    expect(find.text('Riproduci ora'), findsOneWidget);
    expect(find.byKey(fillKey), findsNothing);
    await tester.pump(const Duration(seconds: 20));
    expect(played, 0);

    countdown.value = true;
    await tester.pump();
    expect(find.text('Riproduci ora · 10'), findsOneWidget,
        reason: 'riparte da capo');
    await tester.pump(const Duration(seconds: 10));
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
    expect(find.byKey(fillKey), findsNothing);
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
