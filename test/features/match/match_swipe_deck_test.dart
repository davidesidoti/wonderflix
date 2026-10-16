import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/match/match_swipe_deck.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

final votes = <bool>[];

/// Come la pagina: la carta votata esce dal mazzo.
class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final cards = [
    testItem(id: 'm1', name: 'Uno'),
    testItem(id: 'm2', name: 'Due'),
    testItem(id: 'm3', name: 'Tre'),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 500,
        child: MatchSwipeDeck(
          cards: List.of(cards),
          onVote: (yes) {
            votes.add(yes);
            setState(() => cards.removeAt(0));
          },
        ),
      );
}

void main() {
  setUp(votes.clear);

  Future<void> pumpDeck(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) {
    return pumpApp(tester, const Scaffold(body: Center(child: _Page())),
        motion: motion);
  }

  final top = find.text('Uno');
  double labelOpacity(WidgetTester tester, String key) =>
      tester.widget<Opacity>(find.byKey(Key(key))).opacity;

  testWidgets('dragPastTheThresholdVotes', (tester) async {
    await pumpDeck(tester);
    final width = tester.getSize(find.byType(MatchSwipeDeck)).width;

    await tester.drag(top, Offset(width * 0.35, 0));
    await tester.pumpAndSettle();
    expect(votes, [true]);

    await tester.drag(find.text('Due'), Offset(-width * 0.35, 0));
    await tester.pumpAndSettle();
    expect(votes, [true, false]);
  });

  testWidgets('aShortDragGoesBack', (tester) async {
    await pumpDeck(tester);
    final width = tester.getSize(find.byType(MatchSwipeDeck)).width;
    final start = tester.getCenter(top);

    final gesture = await tester.startGesture(start);
    await gesture.moveBy(Offset(width * 0.1, 0));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(votes, isEmpty);
    expect(tester.getCenter(top).dx, closeTo(start.dx, 0.5));
  });

  testWidgets('aFlingVotes', (tester) async {
    await pumpDeck(tester);

    await tester.fling(top, const Offset(60, 0), 1500);
    await tester.pumpAndSettle();

    expect(votes, [true]);
  });

  testWidgets('labelsShowWhileDragging', (tester) async {
    await pumpDeck(tester);
    final width = tester.getSize(find.byType(MatchSwipeDeck)).width;

    final gesture = await tester.startGesture(tester.getCenter(top));
    await gesture.moveBy(Offset(width * 0.15, 0));
    await tester.pump();

    expect(labelOpacity(tester, 'match-label-yes'), inExclusiveRange(0, 1));
    expect(labelOpacity(tester, 'match-label-no'), 0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('buttonsAndArrowKeysVote', (tester) async {
    await pumpDeck(tester);

    await tester.tap(find.byKey(const Key('match-no')));
    await tester.pumpAndSettle();
    expect(votes, [false]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(votes, [false, true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(votes, [false, true, false]);
  });

  testWidgets('aHeldKeyVotesOncePerCard', (tester) async {
    await pumpDeck(tester, motion: MotionLevel.full);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.tap(find.byKey(const Key('match-yes')));
    await tester.pumpAndSettle();

    expect(votes, [true]);
  });

  testWidgets('reducedMotionStillVotes', (tester) async {
    await pumpDeck(tester);

    await tester.tap(find.byKey(const Key('match-yes')));
    await tester.pumpAndSettle();

    expect(votes, [true]);
  });
}
