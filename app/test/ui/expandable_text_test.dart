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

  testWidgets('aperto con un tetto: expandedMaxLines righe', (t) async {
    final long = 'Una trama lunga che va su più righe. ' * 60;
    await pumpApp(
      t,
      Scaffold(
        body: SizedBox(
          width: 400,
          child: ExpandableText(long, maxLines: 3, expandedMaxLines: 10),
        ),
      ),
    );
    await t.tap(find.text('Altro'));
    await t.pump();
    expect(t.widget<Text>(find.text(long)).maxLines, 10);
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
