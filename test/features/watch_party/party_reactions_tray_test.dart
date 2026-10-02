import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/features/watch_party/party_reactions_tray.dart';

import '../../support/pump_app.dart';

void main() {
  late List<PartyReaction> sent;
  late int closed;
  late ValueNotifier<bool> open;

  setUp(() {
    sent = [];
    closed = 0;
    open = ValueNotifier(true);
  });

  Future<void> pumpTray(WidgetTester tester) => pumpApp(
        tester,
        Scaffold(
          body: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: open,
              builder: (context, isOpen, _) => PartyReactionsTray(
                open: isOpen,
                onReaction: sent.add,
                onClose: () {
                  closed++;
                  open.value = false;
                },
              ),
            ),
          ),
        ),
      );

  testWidgets('sei emoji con il tasto e l\'etichetta', (tester) async {
    await pumpTray(tester);
    for (final reaction in PartyReaction.values) {
      expect(find.text(reaction.emoji), findsOneWidget);
      expect(find.text('${reaction.key}'), findsOneWidget);
    }
    expect(find.byTooltip('Risata'), findsOneWidget);
    expect(find.byTooltip('Facepalm'), findsOneWidget);
  });

  testWidgets('un clic manda la reazione e la barretta resta aperta',
      (tester) async {
    await pumpTray(tester);
    await tester.tap(find.byKey(const ValueKey('party-reaction-clap')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('party-reaction-joy')));
    await tester.pump();
    expect(sent, [PartyReaction.clap, PartyReaction.joy]);
    expect(closed, 0);
  });

  testWidgets('si chiude da sola dopo 5 s senza il mouse sopra; '
      'con il mouse sopra no', (tester) async {
    await pumpTray(tester);
    await tester.pump(
        PartyReactionsTray.idleClose - const Duration(milliseconds: 1));
    expect(closed, 0);
    final mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(PartyReactionsTray)));
    await tester.pump(PartyReactionsTray.idleClose * 2);
    expect(closed, 0, reason: 'mouse sopra');
    await mouse.moveTo(Offset.zero);
    await tester.pump(PartyReactionsTray.idleClose);
    expect(closed, 1);
  });

  testWidgets('un clic fa ripartire i 5 s', (tester) async {
    await pumpTray(tester);
    const step = Duration(seconds: 4);
    await tester.pump(step);
    await tester.tap(find.byKey(const ValueKey('party-reaction-wow')));
    await tester.pump(step);
    expect(closed, 0);
    await tester.pump(PartyReactionsTray.idleClose - step);
    expect(closed, 1);
  });

  testWidgets('chiusa dal genitore: il timer dei 5 s non scatta più',
      (tester) async {
    await pumpTray(tester);
    await tester.pump(const Duration(seconds: 2));
    open.value = false;
    await tester.pump();
    await tester.pump(PartyReactionsTray.idleClose * 2);
    expect(closed, 0);
  });

  testWidgets('chiusa: invisibile e senza clic', (tester) async {
    open.value = false;
    await pumpTray(tester);
    await tester.pumpAndSettle();
    final opacity = tester.widget<AnimatedOpacity>(find.descendant(
        of: find.byType(PartyReactionsTray),
        matching: find.byType(AnimatedOpacity)));
    expect(opacity.opacity, 0);
    await tester.tap(find.byKey(const ValueKey('party-reaction-joy')),
        warnIfMissed: false);
    expect(sent, isEmpty);
  });
}
