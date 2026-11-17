import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/inbox/inbox_row.dart';

import '../../support/pump_app.dart';

void main() {
  Widget row({
    bool highlighted = false,
    String sentence = 'Ciao',
    Widget? action,
    VoidCallback? onOpen,
    VoidCallback? onRemove,
  }) =>
      Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 380,
            child: InboxRow(
              highlighted: highlighted,
              leading: const SizedBox(width: 40, height: 40),
              sentence: TextSpan(text: sentence),
              meta: 'adesso',
              action: action,
              onOpen: onOpen,
              onRemove: onRemove ?? () {},
            ),
          ),
        ),
      );

  Opacity removeOpacity(WidgetTester t) => t.widget<Opacity>(find.ancestor(
      of: find.byTooltip('Togli dalla lista'), matching: find.byType(Opacity)));

  testWidgets('la ✕ si vede sempre al 40%, piena col mouse', (t) async {
    var removed = 0;
    await pumpApp(t, row(onRemove: () => removed++));
    expect(removeOpacity(t).opacity, 0.4);

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.text('adesso')));
    await t.pump();
    expect(removeOpacity(t).opacity, 1);

    await t.tap(find.byTooltip('Togli dalla lista'));
    expect(removed, 1);
  });

  testWidgets('Tab arriva alla riga, poi alla ✕, che si accende', (t) async {
    await pumpApp(t, row(onOpen: () {}));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(removeOpacity(t).opacity, 0.4);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(removeOpacity(t).opacity, 1);
  });

  testWidgets('tutta la riga apre; senza onOpen niente', (t) async {
    var opened = 0;
    await pumpApp(t, row(onOpen: () => opened++));
    await t.tap(find.text('adesso'));
    expect(opened, 1);

    await pumpApp(t, row());
    await t.tap(find.text('adesso'));
    expect(t.takeException(), isNull);
    expect(opened, 1);
  });

  testWidgets('evidenziata: pallino e fondo più chiaro', (t) async {
    await pumpApp(t, row());
    expect(find.byKey(const Key('inbox-unread')), findsNothing);

    await pumpApp(t, row(highlighted: true));
    expect(find.byKey(const Key('inbox-unread')), findsOneWidget);
    final fill = WfColors.surfaceHigh.withValues(alpha: 0.5);
    final boxes = t.widgetList<ColoredBox>(
        find.ancestor(of: find.text('Ciao'), matching: find.byType(ColoredBox)));
    expect(boxes.any((b) => b.color == fill), isTrue);
  });

  testWidgets('nome lungo, testo a 1,5, larga 380: niente overflow', (t) async {
    await pumpApp(
      t,
      MediaQuery(
        data: const MediaQueryData(
            size: Size(380, 800), textScaler: TextScaler.linear(1.5)),
        child: row(
          highlighted: true,
          sentence: '${'Bartolomeo' * 6} ti invita a guardare un film',
          action: TextButton(onPressed: () {}, child: const Text('Unisciti')),
          onOpen: () {},
        ),
      ),
      surfaceSize: const Size(380, 800),
    );
    expect(t.takeException(), isNull);
    expect(t.getTopRight(find.byTooltip('Togli dalla lista')).dx,
        lessThanOrEqualTo(380));
    expect(t.getTopRight(find.text('Unisciti')).dx, lessThanOrEqualTo(380));
  });
}
