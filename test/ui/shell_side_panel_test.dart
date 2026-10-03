import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/shell_side_panel.dart';

import '../support/pump_app.dart';

void main() {
  const scrim = Key('test-scrim');
  var closes = 0;

  setUp(() => closes = 0);

  /// Monta il pannello; il `ValueNotifier` che si ritorna lo apre e lo
  /// chiude.
  Future<ValueNotifier<bool>> pumpPanel(WidgetTester tester,
      {bool open = true, bool Function()? onEscape}) async {
    final isOpen = ValueNotifier(open);
    addTearDown(isOpen.dispose);
    await pumpApp(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: isOpen,
        builder: (context, open, _) => ShellSidePanel(
          open: open,
          onClose: () => closes++,
          scrimKey: scrim,
          onEscape: onEscape,
          child: const ColoredBox(
              color: Colors.white, child: Center(child: Text('contenuto'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return isOpen;
  }

  testWidgets('Esc a pannello aperto: se il contenuto non lo usa, chiude',
      (tester) async {
    await pumpPanel(tester, onEscape: () => false);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    expect(closes, 1);
  });

  testWidgets('Esc usato dal contenuto: il pannello non si chiude',
      (tester) async {
    await pumpPanel(tester, onEscape: () => true);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    expect(closes, 0);
  });

  testWidgets('Esc senza onEscape: chiude', (tester) async {
    await pumpPanel(tester);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    expect(closes, 1);
  });

  testWidgets('Esc a pannello chiuso: ignorato', (tester) async {
    await pumpPanel(tester, open: false, onEscape: () => false);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
    expect(closes, 0);
  });

  testWidgets('un clic sullo scuro chiude; lo scuro ha l\'opacità fissata',
      (tester) async {
    await pumpPanel(tester);
    final tint = tester.widget<ColoredBox>(find.descendant(
        of: find.byKey(scrim), matching: find.byType(ColoredBox)));
    expect(tint.color,
        Colors.black.withValues(alpha: ShellSidePanel.scrimOpacity));

    await tester.tapAt(const Offset(100, 500));
    expect(closes, 1);
  });

  testWidgets('mentre il pannello si chiude, un clic sullo scuro non conta',
      (tester) async {
    final isOpen = await pumpPanel(tester);

    isOpen.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(scrim), findsOneWidget, reason: 'sta ancora uscendo');

    // Nel frattempo un altro pannello può essersi aperto: il clic non deve
    // chiuderlo.
    await tester.tapAt(const Offset(100, 500));
    expect(closes, 0);

    await tester.pumpAndSettle();
    expect(find.byKey(scrim), findsNothing);
  });
}
