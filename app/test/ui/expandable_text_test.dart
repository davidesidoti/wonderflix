import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/expandable_text.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('testo lungo: tre righe e Altro, che lo apre', (t) async {
    final long = 'Una trama lunga che va su più righe. ' * 20;
    await pumpApp(
      t,
      Scaffold(
        body: SizedBox(width: 400, child: ExpandableText(long, maxLines: 3)),
      ),
    );
    expect(t.widget<Text>(find.text(long)).maxLines, 3);
    await t.tap(find.text('Altro'));
    await t.pump();
    expect(t.widget<Text>(find.text(long)).maxLines, isNull);
    expect(find.text('Altro'), findsNothing);
  });

  testWidgets('aperto con un tetto: alto al più 6 righe, e scorre', (t) async {
    final long = 'Una trama lunga che va su più righe. ' * 60;
    await pumpApp(
      t,
      Scaffold(
        body: SizedBox(
          width: 400,
          child: ExpandableText(
            long,
            maxLines: 3,
            expandedMaxLines: 6,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
      ),
    );
    await t.tap(find.text('Altro'));
    await t.pump();
    final box = find.ancestor(
      of: find.text(long),
      matching: find.byType(SingleChildScrollView),
    );
    expect(t.getSize(box).height, 6 * 14 * 1.5);
    final position = t.state<ScrollableState>(find.descendant(
      of: box,
      matching: find.byType(Scrollable),
    )).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await t.drag(box, const Offset(0, -5000));
    await t.pump();
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.01));
  });

  testWidgets('Altro con la tastiera: Tab porta qui, Invio apre', (t) async {
    final long = 'Una trama lunga che va su più righe. ' * 20;
    await pumpApp(
      t,
      Scaffold(
        body: SizedBox(width: 400, child: ExpandableText(long, maxLines: 3)),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('Altro'), findsNothing);
    expect(t.widget<Text>(find.text(long)).maxLines, isNull);
  });

  testWidgets('testo corto: niente Altro', (t) async {
    await pumpApp(
      t,
      const Scaffold(body: ExpandableText('Breve.', maxLines: 3)),
    );
    expect(find.text('Altro'), findsNothing);
  });

  testWidgets('in TV il testo ha il focus e OK lo apre', (t) async {
    final long = 'Una trama lunga che va su più righe. ' * 20;
    await pumpApp(
      t,
      Scaffold(
        body: SizedBox(
          width: 400,
          child: ExpandableText(long, maxLines: 3, tvFocusable: true),
        ),
      ),
      tv: true,
    );
    expect(find.text('Altro'), findsOneWidget);
    // Il focus lo prende col telecomando: OK sul testo lo apre.
    Focus.of(t.element(find.text(long)), scopeOk: true).nextFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    expect(t.widget<Text>(find.text(long)).maxLines, isNull);
    expect(find.text('Altro'), findsNothing);
  });
}
