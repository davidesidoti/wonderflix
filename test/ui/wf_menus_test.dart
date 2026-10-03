import 'package:flutter/material.dart';
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

  testWidgets('menu ancorato: sotto il pulsante, sopra se sotto non ci sta',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final top = GlobalKey();
    final bottom = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        Positioned(
            left: 100,
            top: 20,
            width: 80,
            height: 40,
            child: SizedBox(key: top)),
        Positioned(
            left: 100,
            top: 540,
            width: 80,
            height: 40,
            child: SizedBox(key: bottom)),
      ]),
    ));
    const height = 200.0;
    final below =
        menuPositionBelow(top.currentContext!, estimatedHeight: height);
    expect(below.top, 60, reason: 'sotto il pulsante in alto');
    expect(below.left, 100);
    final above =
        menuPositionBelow(bottom.currentContext!, estimatedHeight: height);
    expect(above.top, 540 - height,
        reason: 'il pulsante in basso: il menu finisce dove inizia lui');
    expect(above.left, 100);
    expect(menuPositionBelow(bottom.currentContext!).top, 580,
        reason: 'senza altezza prevista: sempre sotto');
  });
}
