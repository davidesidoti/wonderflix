import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/sliding_underline.dart';

void main() {
  final keys = {for (final k in ['a', 'b', 'c']) k: GlobalKey()};

  Widget tree(String? selected) => Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: const WfMotion(MotionLevel.full),
          child: Align(
            alignment: Alignment.topLeft,
            child: SlidingUnderline(
              selected: selected,
              itemKeys: keys,
              indicatorKey: const Key('linea'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final k in ['a', 'b', 'c'])
                  SizedBox(key: keys[k], width: k == 'b' ? 120 : 60, height: 30),
              ]),
            ),
          ),
        ),
      );

  testWidgets('sotto l\'elemento scelto, poi scorre al nuovo', (tester) async {
    await tester.pumpWidget(tree('a'));
    await tester.pump();
    expect(tester.getRect(find.byKey(const Key('linea'))).left, 0);
    await tester.pumpWidget(tree('b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.getRect(find.byKey(const Key('linea'))).left;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(60));
    await tester.pumpAndSettle();
    final line = tester.getRect(find.byKey(const Key('linea')));
    expect(line.left, 60);
    expect(line.width, 120);
    expect(line.height, 2);
  });

  testWidgets('nessuna scelta: nessuna linea', (tester) async {
    await tester.pumpWidget(tree(null));
    await tester.pump();
    expect(find.byKey(const Key('linea')), findsNothing);
  });
}
