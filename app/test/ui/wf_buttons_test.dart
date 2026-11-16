import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../support/pump_app.dart';

void main() {
  double scaleOf(WidgetTester tester, Finder target) => tester
      .widget<AnimatedScale>(
          find.ancestor(of: target, matching: find.byType(AnimatedScale)).first)
      .scale;

  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
    return mouse;
  }

  testWidgets('WfButton: scala e alone oro al passaggio del mouse',
      (tester) async {
    await pumpApp(
      tester,
      Center(
        child: WfButton.primary(
            label: 'Riproduci', icon: LucideIcons.play, onPressed: () {}),
      ),
      motion: MotionLevel.full,
    );
    final label = find.text('Riproduci');
    expect(scaleOf(tester, label), 1);
    await hover(tester, label);
    expect(scaleOf(tester, label), 1.03);
    final glow = tester
        .widget<AnimatedContainer>(find.byKey(const Key('wf-button-glow')));
    expect((glow.decoration! as BoxDecoration).boxShadow, isNotEmpty);
  });

  testWidgets('WfButton ridotto: alone sì, scala no', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: WfButton.secondary(
            label: 'Dettagli', icon: LucideIcons.info, onPressed: () {}),
      ),
    );
    final label = find.text('Dettagli');
    await hover(tester, label);
    expect(scaleOf(tester, label), 1);
  });

  testWidgets('WfButton disattivato: nessun effetto', (tester) async {
    await pumpApp(
      tester,
      const Center(
        child: WfButton.primary(
            label: 'Riproduci', icon: LucideIcons.play, onPressed: null),
      ),
      motion: MotionLevel.full,
    );
    final label = find.text('Riproduci');
    await hover(tester, label);
    expect(scaleOf(tester, label), 1);
  });

  Widget toggleHost() {
    var selected = false;
    return Center(
      child: StatefulBuilder(
        builder: (context, setState) => WfIconToggle(
          icon: LucideIcons.heart,
          selected: selected,
          tooltip: 'La mia lista',
          onPressed: () => setState(() => selected = !selected),
        ),
      ),
    );
  }

  double popScale(WidgetTester tester) => tester
      .widget<ScaleTransition>(find.descendant(
          of: find.byType(WfIconToggle), matching: find.byType(ScaleTransition)))
      .scale
      .value;

  testWidgets('WfIconToggle: "pop" quando si attiva', (tester) async {
    await pumpApp(tester, toggleHost(), motion: MotionLevel.full);
    await tester.tap(find.byType(WfIconToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(popScale(tester), greaterThan(1));
    await tester.pumpAndSettle();
    expect(popScale(tester), 1);
    // Disattivando: nessun pop.
    await tester.tap(find.byType(WfIconToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(popScale(tester), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('WfIconToggle ridotto: nessun pop', (tester) async {
    await pumpApp(tester, toggleHost());
    await tester.tap(find.byType(WfIconToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(popScale(tester), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('WfIconToggle: il riempimento segue la durata dei token',
      (tester) async {
    for (final level in MotionLevel.values) {
      await pumpApp(tester, toggleHost(), motion: level);
      final style = tester.widget<IconButton>(find.byType(IconButton)).style!;
      expect(style.animationDuration, WfMotion(level).duration(WfMotion.fast),
          reason: '$level');
    }
  });

  testWidgets('WfButton.secondary gold: testo, icona e bordo oro',
      (tester) async {
    await pumpApp(
      tester,
      Center(
        child: WfButton.secondary(
            label: 'Il tuo voto: 8',
            icon: LucideIcons.pencil,
            gold: true,
            onPressed: () {}),
      ),
    );
    final style = tester
        .widget<OutlinedButton>(find.byType(OutlinedButton))
        .style!;
    expect(style.foregroundColor!.resolve({}), WfColors.gold);
    expect(style.side!.resolve({})!.color, WfColors.gold);
  });

  testWidgets('WfButton.secondary in TV: focus crema sull oro, oro altrimenti',
      (tester) async {
    await pumpApp(
      tester,
      Column(children: [
        WfButton.secondary(
            key: const Key('g'),
            label: 'Il tuo voto: 8',
            icon: LucideIcons.pencil,
            gold: true,
            onPressed: () {}),
        WfButton.secondary(
            key: const Key('n'),
            label: 'Altro',
            icon: LucideIcons.star,
            onPressed: () {}),
      ]),
      surfaceSize: const Size(960, 540),
      tv: true,
    );
    BorderSide? focused(String key) => tester
        .widget<OutlinedButton>(find.descendant(
            of: find.byKey(Key(key)), matching: find.byType(OutlinedButton)))
        .style!
        .side!
        .resolve({WidgetState.focused});
    expect(focused('g'), tvFocusSideOnGold);
    expect(focused('n'), tvFocusSide);
  });
}
