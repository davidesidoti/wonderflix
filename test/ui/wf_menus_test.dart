import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/wf_menus.dart';

void main() {
  testWidgets('menu: durata e curva dai token', (tester) async {
    late AnimationStyle full;
    late AnimationStyle reduced;
    await tester.pumpWidget(WfMotionScope(
      motion: const WfMotion(MotionLevel.full),
      child: Builder(builder: (context) {
        full = wfPopUpAnimation(context);
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(WfMotionScope(
      motion: const WfMotion(MotionLevel.reduced),
      child: Builder(builder: (context) {
        reduced = wfPopUpAnimation(context);
        return const SizedBox();
      }),
    ));
    expect(full.duration, WfMotion.medium);
    expect(full.curve, WfMotion.emphasized);
    expect(full.reverseDuration, WfMotion.fast);
    expect(reduced.duration, WfMotion.fast);
  });
}
