import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/catalog/catalog_filters_bar.dart';
import 'package:wonderflix/ui/tv_focusable.dart';
import 'package:wonderflix/ui/wf_buttons.dart';
import 'package:wonderflix/ui/wf_tab_button.dart';

import '../support/pump_app.dart';

/// Bordo disegnato dal pulsante [button] (il Material dentro di lui).
BorderSide _side(WidgetTester tester, Finder button) {
  final material = tester.widget<Material>(
    find.descendant(of: button, matching: find.byType(Material)).first,
  );
  return (material.shape! as OutlinedBorder).side;
}

/// Bordo disegnato attorno a [child] da un `DecoratedBox` antenato.
Border? _ring(WidgetTester tester, Finder child) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.ancestor(of: child, matching: find.byType(DecoratedBox)),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration &&
        decoration.border is Border &&
        (decoration.border! as Border).top.width == 2) {
      return decoration.border! as Border;
    }
  }
  return null;
}

/// Dà il focus al controllo che contiene [inner] (la sua etichetta o icona).
Future<void> _focus(WidgetTester tester, Finder inner) async {
  Focus.of(tester.element(inner.first)).requestFocus();
  await tester.pumpAndSettle();
}

void main() {
  test('fuori dalla TV il tema non cambia', () {
    final plain = buildWonderflixTheme();
    final notTv = buildWonderflixTheme(tv: false);
    const focused = {WidgetState.focused};
    for (final (a, b) in [
      (plain.filledButtonTheme.style, notTv.filledButtonTheme.style),
      (plain.outlinedButtonTheme.style, notTv.outlinedButtonTheme.style),
      (plain.textButtonTheme.style, notTv.textButtonTheme.style),
    ]) {
      expect(b?.side?.resolve(focused), a?.side?.resolve(focused));
    }
    // Il bordo col focus resta quello di sempre (oro sottile).
    expect(
      plain.outlinedButtonTheme.style?.side?.resolve(focused),
      const BorderSide(color: WfColors.gold),
    );
    expect(plain.filledButtonTheme.style?.side, isNull);
    expect(plain.iconButtonTheme.style, isNull);
    expect(plain.segmentedButtonTheme.style, isNull);
    expect(plain.focusColor, ThemeData.dark(useMaterial3: true).focusColor);
  });

  group('sulla TV il controllo col focus ha il bordo largo 2', () {
    testWidgets('FilledButton (crema: oro su oro non si vede)', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Center(child: FilledButton(onPressed: () {}, child: const Text('A'))),
        tv: true,
      );
      final button = find.byType(FilledButton);
      expect(_side(tester, button).width, isNot(2));
      await _focus(tester, find.text('A'));
      expect(_side(tester, button), tvFocusSideOnGold);
    });

    testWidgets('IconButton', (tester) async {
      await pumpApp(
        tester,
        Center(
          child: IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
        ),
        tv: true,
      );
      final button = find.byType(IconButton);
      await _focus(tester, find.byIcon(Icons.add));
      expect(_side(tester, button), tvFocusSide);
    });

    testWidgets('segmento di SegmentedButton', (tester) async {
      await pumpApp(
        tester,
        Center(
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Uno')),
              ButtonSegment(value: 2, label: Text('Due')),
            ],
            selected: const {1},
            onSelectionChanged: (_) {},
          ),
        ),
        tv: true,
      );
      final segment = find.ancestor(
        of: find.text('Due'),
        matching: find.byType(TextButton),
      );
      await _focus(tester, find.text('Due'));
      // Il segmento ha il focus e il contorno del gruppo diventa quello
      // della TV (lo disegna SegmentedButton, non il segmento).
      expect(Focus.of(tester.element(find.text('Due'))).hasPrimaryFocus, isTrue);
      final side = Theme.of(tester.element(segment))
          .segmentedButtonTheme
          .style
          ?.side;
      expect(side?.resolve({WidgetState.focused}), tvFocusSide);
      expect(side?.resolve({}), isNot(tvFocusSide));
    });

    testWidgets('WfButton.primary e .secondary, WfIconToggle', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WfButton.primary(
                label: 'Riproduci',
                icon: Icons.play_arrow,
                onPressed: () {},
              ),
              WfButton.secondary(
                label: 'Dettagli',
                icon: Icons.info,
                onPressed: () {},
              ),
              WfIconToggle(
                icon: Icons.favorite,
                selected: false,
                tooltip: 'Lista',
                onPressed: () {},
              ),
            ],
          ),
        ),
        tv: true,
      );
      final primary = find.byType(FilledButton);
      final secondary = find.byType(OutlinedButton);
      final toggle = find.byType(IconButton);
      final idle = _side(tester, secondary);
      await _focus(tester, find.text('Riproduci'));
      expect(_side(tester, primary), tvFocusSideOnGold);
      await _focus(tester, find.text('Dettagli'));
      expect(_side(tester, secondary), tvFocusSide);
      expect(_side(tester, primary).width, isNot(2));
      await _focus(tester, find.byIcon(Icons.favorite));
      expect(_side(tester, toggle), tvFocusSide);
      expect(_side(tester, secondary), idle);
    });

    testWidgets('filtri del catalogo e schede', (tester) async {
      await pumpApp(
        tester,
        Material(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilterPicker<int>(
                  value: 1,
                  items: const {1: 'Uno', 2: 'Due'},
                  onChanged: (_) {},
                ),
                WfTabButton(label: 'Film', selected: true, onTap: () {}),
              ],
            ),
          ),
        ),
        tv: true,
      );
      expect(_ring(tester, find.text('Uno'))?.top.color, isNot(tvFocusColor));
      // Col tasto Tab, come le frecce: prima il menu, poi la scheda.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_ring(tester, find.text('Uno'))?.top.color, tvFocusColor);
      expect(_ring(tester, find.text('Film'))?.top.color, isNot(tvFocusColor));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_ring(tester, find.text('Film'))?.top.color, tvFocusColor);
      expect(_ring(tester, find.text('Uno'))?.top.color, isNot(tvFocusColor));
    });
  });

  testWidgets('fuori dalla TV i pulsanti di casa non cambiano col focus', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Center(
        child: WfButton.secondary(
          label: 'Dettagli',
          icon: Icons.info,
          onPressed: () {},
        ),
      ),
    );
    final secondary = find.byType(OutlinedButton);
    final idle = _side(tester, secondary);
    await _focus(tester, find.text('Dettagli'));
    expect(_side(tester, secondary), idle);
  });
}
