import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

void main() {
  Widget grid(int count, {Object? reset, MotionLevel level = MotionLevel.full}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: WfMotion(level),
          child: BatchedEntrance(
            itemCount: count,
            resetKey: reset,
            child: Column(children: [
              for (var i = 0; i < count; i++)
                BatchedEntranceItem(index: i, child: Text('card $i')),
            ]),
          ),
        ),
      );

  double opacityOf(WidgetTester tester, String text) {
    final fades = tester.widgetList<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)));
    return fades.isEmpty ? 1 : fades.first.opacity;
  }

  testWidgets('primo blocco: entrano al massimo 12', (tester) async {
    await tester.pumpWidget(grid(14));
    expect(opacityOf(tester, 'card 0'), 0);
    expect(opacityOf(tester, 'card 12'), 1, reason: 'oltre il massimo');
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'card 0'), 1);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('pagina successiva: entrano solo le nuove', (tester) async {
    await tester.pumpWidget(grid(4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid(8));
    expect(opacityOf(tester, 'card 0'), 1);
    expect(opacityOf(tester, 'card 4'), 0);
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'card 7'), 1);
  });

  testWidgets('elementi tolti: nessuna entrata', (tester) async {
    await tester.pumpWidget(grid(6));
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid(5));
    expect(opacityOf(tester, 'card 0'), 1);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('nuova chiave (filtro): si riparte dall\'inizio', (tester) async {
    await tester.pumpWidget(grid(4, reset: 'a'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid(4, reset: 'b'));
    expect(opacityOf(tester, 'card 0'), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('ridotte: nessuna entrata', (tester) async {
    await tester.pumpWidget(grid(4, level: MotionLevel.reduced));
    expect(opacityOf(tester, 'card 0'), 1);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
