import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/watch_party/invite_card_frame.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/pump_app.dart';

void main() {
  late int timedOut;
  late int joined;

  setUp(() {
    timedOut = 0;
    joined = 0;
  });

  Future<void> pumpFrame(WidgetTester tester,
          {MotionLevel motion = MotionLevel.full, bool newest = true}) =>
      pumpApp(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: InviteCardFrame(
              key: const Key('card'),
              leading: const SizedBox.square(dimension: 40),
              sentence: const TextSpan(text: 'Luigi ti invita a un Match'),
              primaryLabel: 'Unisciti',
              primaryIcon: LucideIcons.play,
              onPrimary: () => joined++,
              secondaryLabel: 'Più tardi',
              secondaryIcon: LucideIcons.clock,
              onSecondary: () {},
              newest: newest,
              onTimeout: () => timedOut++,
            ),
          ),
        ),
        motion: motion,
      );

  testWidgets('si chiude da sola dopo 10 s', (tester) async {
    await pumpFrame(tester);
    expect(find.byKey(const Key('invite-countdown')), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(timedOut, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(timedOut, 1);
  });

  testWidgets('il puntatore sopra la ferma; via, riparte da dove era',
      (tester) async {
    await pumpFrame(tester);
    await tester.pump(const Duration(seconds: 9));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('card'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(timedOut, 0);

    await gesture.moveTo(const Offset(5, 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(timedOut, 0, reason: 'resta il secondo che mancava');
    await tester.pump(const Duration(milliseconds: 200));
    expect(timedOut, 1);
  });

  testWidgets('col focus dentro si ferma', (tester) async {
    await pumpFrame(tester);
    await tester.pump(const Duration(seconds: 5));
    // Tab porta il fuoco sul primo pulsante della carta.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    await tester.pump(const Duration(seconds: 20));
    expect(timedOut, 0);
  });

  testWidgets('movimento ridotto: niente barretta, non si chiude',
      (tester) async {
    await pumpFrame(tester, motion: MotionLevel.reduced);
    expect(find.byKey(const Key('invite-countdown')), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(timedOut, 0);
  });

  testWidgets('solo la più nuova ha il primario oro', (tester) async {
    bool isPrimary(Widget w) => w is WfButton && w.primary;
    await pumpFrame(tester, newest: false);
    expect(find.byWidgetPredicate(isPrimary), findsNothing);
    expect(find.text('Unisciti'), findsOneWidget);
    expect(find.text('Più tardi'), findsOneWidget);

    await pumpFrame(tester);
    expect(find.byWidgetPredicate(isPrimary), findsOneWidget);
    await tester.tap(find.text('Unisciti'));
    expect(joined, 1);
  });
}
