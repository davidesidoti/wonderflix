import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/smooth_scroll.dart';

void main() {
  const step = 60 * wheelScrollMultiplier;

  Future<SmoothScrollController> pumpList(WidgetTester tester) async {
    final controller = SmoothScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ListView.builder(
        controller: controller,
        itemCount: 100,
        itemExtent: 100,
        itemBuilder: (context, i) => Text('riga $i'),
      ),
    ));
    return controller;
  }

  Future<void> wheel(WidgetTester tester, Finder target, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(target)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  }

  testWidgets('uno scatto arriva a destinazione in modo animato', (tester) async {
    final controller = await pumpList(tester);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(step));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(step, 0.01));
  });

  testWidgets('gli scatti ravvicinati si sommano', (tester) async {
    final controller = await pumpList(tester);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pump(const Duration(milliseconds: 50));
    await wheel(tester, find.byType(ListView), 60);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(2 * step, 0.01));
  });

  testWidgets('la destinazione resta nei limiti', (tester) async {
    final controller = await pumpList(tester);
    final max = controller.position.maxScrollExtent;
    controller.jumpTo(max - 20);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pumpAndSettle();
    expect(controller.offset, max);
    await wheel(tester, find.byType(ListView), -60);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(max - step, 0.01));
  });

  testWidgets('jumpTo annulla la destinazione in sospeso', (tester) async {
    final controller = await pumpList(tester);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pump(const Duration(milliseconds: 50));
    controller.jumpTo(500);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(500 + step, 0.01));
  });

  testWidgets('un trascinamento annulla la destinazione in sospeso',
      (tester) async {
    final controller = await pumpList(tester);
    await wheel(tester, find.byType(ListView), 60);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final afterDrag = controller.offset;
    await wheel(tester, find.byType(ListView), 60);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(afterDrag + step, 0.01));
  });

  testWidgets('rotella verticale sopra una riga orizzontale: scorre la pagina',
      (tester) async {
    final page = SmoothScrollController();
    final row = SmoothScrollController();
    addTearDown(page.dispose);
    addTearDown(row.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ListView(
        controller: page,
        children: [
          SizedBox(
            height: 200,
            child: ListView.builder(
              key: const Key('row'),
              controller: row,
              scrollDirection: Axis.horizontal,
              itemCount: 50,
              itemExtent: 150,
              itemBuilder: (context, i) => Text('card $i'),
            ),
          ),
          for (var i = 0; i < 30; i++) SizedBox(height: 100, child: Text('riga $i')),
        ],
      ),
    ));
    await wheel(tester, find.byKey(const Key('row')), 60);
    await tester.pumpAndSettle();
    expect(page.offset, closeTo(step, 0.01));
    expect(row.offset, 0);
  });
}
