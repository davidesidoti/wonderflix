import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/form_factor.dart';
import 'package:wonderflix/ui/tv_focusable.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

Future<void> _pump(WidgetTester tester, Widget child, {bool tv = true}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FormFactorScope(tv: tv, child: child)),
      ),
    );

void main() {
  test('costanti', () {
    expect(tvFocusColor, WfColors.gold);
    expect(tvFocusScale, 1.05);
  });

  testWidgets('con il focus: bordo oro largo 2 e scala', (tester) async {
    await _pump(
      tester,
      TvFocusable(
        autofocus: true,
        onActivate: () {},
        child: const SizedBox(key: Key('c'), width: 100, height: 50),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.widget<DecoratedBox>(
      find.ancestor(
        of: find.byKey(const Key('c')),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final border = (box.decoration as BoxDecoration).border! as Border;
    expect(border.top.color, tvFocusColor);
    expect(border.top.width, 2);
    final scale = tester.widget<AnimatedScale>(
      find.ancestor(
        of: find.byKey(const Key('c')),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.scale, tvFocusScale);
  });

  for (final key in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
  ]) {
    testWidgets('${key.keyLabel} attiva una volta', (tester) async {
      var n = 0;
      await _pump(
        tester,
        TvFocusable(
          autofocus: true,
          onActivate: () => n++,
          child: const SizedBox(width: 100, height: 50),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(n, 1);
    });
  }

  testWidgets('il focus porta l elemento in vista', (tester) async {
    final nodes = List.generate(20, (_) => FocusNode());
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });
    await _pump(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 600,
          height: 100,
          // SingleChildScrollView: tutti gli elementi costruiti, FocusNode attaccati
          child: SingleChildScrollView(
            key: const Key('list'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < 20; i++)
                  TvFocusable(
                    focusNode: nodes[i],
                    onActivate: () {},
                    child: SizedBox(key: Key('i$i'), width: 200, height: 100),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final viewport = tester.getRect(find.byKey(const Key('list')));
    nodes[14].requestFocus();
    await tester.pumpAndSettle();
    final r = tester.getRect(find.byKey(const Key('i14')));
    expect(viewport.contains(r.center), isTrue);
    expect(r.left >= viewport.left && r.right <= viewport.right, isTrue);
  });

  testWidgets('fuori dalla TV restituisce il figlio', (tester) async {
    await _pump(
      tester,
      TvFocusable(
        onActivate: () {},
        child: const SizedBox(key: Key('c'), width: 100, height: 50),
      ),
      tv: false,
    );
    expect(
      find.descendant(
        of: find.byType(TvFocusable),
        matching: find.byType(Focus),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(TvFocusable),
        matching: find.byType(AnimatedScale),
      ),
      findsNothing,
    );
  });

  testWidgets('il tasto OK (select) preme un pulsante col focus', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FormFactorScope(
          tv: true,
          child: Shortcuts(shortcuts: tvActivateShortcuts, child: child!),
        ),
        home: Scaffold(
          body: ElevatedButton(
            autofocus: true,
            onPressed: () => pressed++,
            child: const Text('ok'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(pressed, 1);
  });

  // Una pagina lunga col pulsante in fondo, fuori dallo schermo (600 px).
  Widget farButton() => SingleChildScrollView(
    child: Column(
      children: [
        const SizedBox(height: 2000),
        WfButton.primary(
          key: const Key('far'),
          label: 'Lontano',
          icon: Icons.play_arrow,
          autofocus: true,
          onPressed: () {},
        ),
      ],
    ),
  );

  bool onScreen(WidgetTester tester) {
    // Il margine del bersaglio del tocco può sporgere di qualche pixel.
    final rect = tester.getRect(find.byKey(const Key('far'))).deflate(4);
    return rect.top >= 0 && rect.bottom <= 600;
  }

  testWidgets('sulla TV un pulsante qualsiasi col focus scorre in vista', (
    tester,
  ) async {
    await _pump(tester, farButton());
    await tester.pumpAndSettle();

    expect(onScreen(tester), isTrue);
  });

  testWidgets('fuori dalla TV il focus non fa scorrere', (tester) async {
    await _pump(tester, farButton(), tv: false);
    await tester.pumpAndSettle();

    expect(onScreen(tester), isFalse);
  });
}
