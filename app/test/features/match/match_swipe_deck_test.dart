import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/match/match_card.dart';
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
    testItem(
        id: 'm1',
        name: 'Uno',
        year: 2021,
        runtimeMinutes: 155,
        genres: const ['Science Fiction', 'Drama']),
    testItem(id: 'm2', name: 'Due'),
    testItem(id: 'm3', name: 'Tre'),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 500,
        child: MatchSwipeDeck(
          cards: List.of(cards),
          onVote: (yes) async {
            votes.add(yes);
            setState(() => cards.removeAt(0));
            return true;
          },
        ),
      );
}

void main() {
  setUp(votes.clear);

  Future<void> pumpDeck(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced,
      Size surfaceSize = const Size(1280, 800)}) {
    return pumpApp(tester, const Scaffold(body: Center(child: _Page())),
        motion: motion, surfaceSize: surfaceSize);
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

  final topCard = find.byKey(const ValueKey('m1'));

  testWidgets('la carta è verticale, larga 270, col nome in Bebas 34',
      (tester) async {
    await pumpDeck(tester);

    final size = tester.getSize(topCard);
    expect(size.width, 270);
    expect(size.height, 405);
    expect(tester.widget<Text>(top).style?.fontSize, 34);
    expect(tester.widget<Text>(top).style?.fontFamily, WfText.displayFamily);
    expect(find.text('2021 · 2h 35m · Fantascienza · Dramma'), findsOneWidget);
    expect(find.byType(MatchCard), findsNWidgets(3));
  });

  testWidgets('nello stretto la carta è larga 250 e i pulsanti senza scritte',
      (tester) async {
    await pumpDeck(tester, surfaceSize: const Size(390, 780));

    expect(tester.getSize(topCard).width, 250);
    expect(find.text('No · ←'), findsNothing);
    expect(find.text('Sì · →'), findsNothing);
    final no = tester.getRect(find.byKey(const Key('match-no')));
    final yes = tester.getRect(find.byKey(const Key('match-yes')));
    expect(yes.left - no.right, 56);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulsanti tondi da 64 con i tasti sotto e "Ne restano"',
      (tester) async {
    await pumpDeck(tester);

    final no = tester.getRect(find.byKey(const Key('match-no')));
    final yes = tester.getRect(find.byKey(const Key('match-yes')));
    expect(no.size, const Size(64, 64));
    expect(yes.size, const Size(64, 64));
    expect(yes.left - no.right, 44);
    expect(tester.getTopLeft(find.text('No · ←')).dy, greaterThan(no.bottom));
    expect(tester.getTopLeft(find.text('Sì · →')).dy, greaterThan(yes.bottom));
    expect(find.text('Ne restano 3'), findsOneWidget);
  });

  testWidgets('con una carta sola dice "Ne resta 1"', (tester) async {
    await pumpApp(
        tester,
        Scaffold(
            body: Center(
                child: SizedBox(
                    width: 500,
                    child: MatchSwipeDeck(
                        cards: [testItem(id: 'm1', name: 'Uno')],
                        onVote: (_) async => true)))),
        motion: MotionLevel.reduced,
        surfaceSize: const Size(1280, 800));

    expect(find.text('Ne resta 1'), findsOneWidget);
  });

  testWidgets('durante il trascinamento compaiono i timbri SÌ e NO',
      (tester) async {
    await pumpDeck(tester);

    expect(tester.widget<Text>(find.text('SÌ')).style?.color, WfColors.online);
    expect(tester.widget<Text>(find.text('NO')).style?.color, WfColors.error);
    expect(tester.widget<Text>(find.text('SÌ')).style?.fontSize, 34);
  });
}
