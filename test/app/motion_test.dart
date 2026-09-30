import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';

void main() {
  test('pick e duration seguono il livello', () {
    const full = WfMotion(MotionLevel.full);
    const reduced = WfMotion(MotionLevel.reduced);
    expect(full.isReduced, isFalse);
    expect(reduced.isReduced, isTrue);
    expect(full.pick(full: 1, reduced: 2), 1);
    expect(reduced.pick(full: 1, reduced: 2), 2);
    expect(full.duration(WfMotion.slow), WfMotion.slow);
    expect(reduced.duration(WfMotion.slow), WfMotion.fast);
    expect(const WfMotion(MotionLevel.full), full);
  });

  testWidgets('of: livello dello scope, ridotto se manca', (tester) async {
    late WfMotion outside;
    late WfMotion inside;
    await tester.pumpWidget(Builder(builder: (context) {
      outside = WfMotion.of(context);
      return WfMotionScope(
        motion: const WfMotion(MotionLevel.full),
        child: Builder(builder: (context) {
          inside = WfMotion.of(context);
          return const SizedBox();
        }),
      );
    }));
    expect(outside.level, MotionLevel.reduced);
    expect(inside.level, MotionLevel.full);
  });

  testWidgets('lo scope avvisa chi dipende quando cambia il livello',
      (tester) async {
    var builds = 0;
    Widget tree(MotionLevel level) => WfMotionScope(
          motion: WfMotion(level),
          child: Builder(builder: (context) {
            WfMotion.of(context);
            builds++;
            return const SizedBox();
          }),
        );
    await tester.pumpWidget(tree(MotionLevel.full));
    await tester.pumpWidget(tree(MotionLevel.full));
    final afterSame = builds;
    await tester.pumpWidget(tree(MotionLevel.reduced));
    expect(builds, afterSame + 1);
  });
}
