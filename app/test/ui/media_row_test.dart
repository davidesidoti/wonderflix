import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/media_row.dart';

import '../support/pump_app.dart';

void main() {
  Widget row(
    String title, {
    int cards = 20,
    String? count,
    Widget? trailing,
  }) => MediaRow(
    title: title,
    height: 60,
    itemCount: cards,
    count: count,
    trailing: trailing,
    itemBuilder: (context, i) => const SizedBox(width: 160),
  );

  const next = Key('row-next');
  const previous = Key('row-previous');

  IconButton button(WidgetTester tester, Key key) =>
      tester.widget<IconButton>(find.byKey(key));

  testWidgets('frecce sul bordo destro con titoli di lunghezze diverse', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Column(
        children: [
          row('Continua a guardare'),
          row('Film in arrivo'),
        ],
      ),
      surfaceSize: const Size(1280, 800),
    );
    final edges = [
      for (final e in find.byKey(next).evaluate())
        tester.getTopRight(find.byElementPredicate((x) => x == e)).dx,
    ];
    expect(edges, hasLength(2));
    expect(edges[0], closeTo(edges[1], 0.5));
    expect(edges[0], closeTo(1280 - 32, 1));
  });

  testWidgets('niente frecce se la riga non scorre', (tester) async {
    await pumpApp(
      tester,
      row('Poche', cards: 3),
      surfaceSize: const Size(1280, 800),
    );
    expect(find.byKey(next), findsNothing);
    expect(find.byKey(previous), findsNothing);
  });

  testWidgets('freccia spenta al capo raggiunto', (tester) async {
    await pumpApp(
      tester,
      row('Tante'),
      surfaceSize: const Size(1280, 800),
    );
    expect(button(tester, previous).onPressed, isNull);
    expect(button(tester, next).onPressed, isNotNull);

    await tester.drag(find.byType(ListView), const Offset(-5000, 0));
    await tester.pumpAndSettle();
    expect(button(tester, previous).onPressed, isNotNull);
    expect(button(tester, next).onPressed, isNull);
  });

  testWidgets('niente frecce col tocco', (tester) async {
    await pumpApp(tester, row('Tante'), touch: true);
    expect(find.byKey(next), findsNothing);
    expect(find.byKey(previous), findsNothing);
  });

  testWidgets('niente frecce in TV', (tester) async {
    await pumpApp(tester, row('Tante'), tv: true);
    expect(find.byKey(next), findsNothing);
    expect(find.byKey(previous), findsNothing);
  });

  testWidgets('conteggio accanto al titolo', (tester) async {
    await pumpApp(
      tester,
      row('Da vedere', count: '9 da guardare'),
      surfaceSize: const Size(1280, 800),
    );
    final title = tester.getRect(find.text('Da vedere'));
    final count = tester.getRect(find.text('9 da guardare'));
    expect(count.left, greaterThan(title.right));
    expect(count.center.dy, closeTo(title.center.dy, 4));
  });

  testWidgets('trailing sotto il titolo nello stretto', (tester) async {
    await pumpApp(
      tester,
      row('Da vedere', trailing: const Text('X')),
      surfaceSize: const Size(390, 780),
    );
    expect(
      tester.getTopLeft(find.text('X')).dy,
      greaterThan(tester.getBottomLeft(find.text('Da vedere')).dy),
    );
  });

  testWidgets('trailing sulla riga del titolo nel largo', (tester) async {
    await pumpApp(
      tester,
      row('Da vedere', trailing: const Text('X')),
      surfaceSize: const Size(1280, 800),
    );
    expect(
      tester.getTopLeft(find.text('X')).dy,
      lessThan(tester.getBottomLeft(find.text('Da vedere')).dy),
    );
  });
}
