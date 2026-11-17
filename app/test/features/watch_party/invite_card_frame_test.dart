import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/invite_card_frame.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

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
    final focused = FocusManager.instance.primaryFocus?.context;
    var inside = false;
    focused?.visitAncestorElements((element) {
      inside = element.widget.key == const Key('card');
      return !inside;
    });
    expect(inside, isTrue, reason: 'il fuoco è dentro la carta');
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

  testWidgets('la carta che sfuma non chiude quella appena arrivata',
      (tester) async {
    final shown = ValueNotifier(1);
    addTearDown(shown.dispose);
    final timedOutIds = <int>[];
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: shown,
          builder: (context, id, _) => InviteCardSlot(
            id: id,
            card: InviteCardFrame(
              leading: const SizedBox.square(dimension: 40),
              sentence: TextSpan(text: 'invito $id'),
              primaryLabel: 'Unisciti',
              primaryIcon: LucideIcons.play,
              onPrimary: () {},
              secondaryLabel: 'Più tardi',
              secondaryIcon: LucideIcons.clock,
              onSecondary: () {},
              newest: true,
              onTimeout: () => timedOutIds.add(id),
            ),
          ),
        ),
      ),
      motion: MotionLevel.full,
    );
    await tester.pump(const Duration(milliseconds: 9800));
    shown.value = 2;
    await tester.pump();
    // Oltre i 10 s della prima, durante e dopo la dissolvenza.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(WfMotion.medium);
    expect(timedOutIds, isEmpty);
    expect(find.text('invito 2'), findsOneWidget);
  });

  test('col cambio di profilo nessuna carta è più la più nuova', () {
    final session = FakeSessionController(const SessionSignedIn(testUser));
    final c = ProviderContainer.test(
        overrides: [sessionControllerProvider.overrideWith(() => session)]);
    c.listen(newestInviteProvider, (_, _) {});
    c.read(newestInviteProvider.notifier).set(InviteKind.party);
    expect(c.read(newestInviteProvider), InviteKind.party);
    session.quickConnectApproved(const JellyfinUser(id: 'u2', name: 'Luigi'));
    expect(c.read(newestInviteProvider), isNull);
  });
}
