import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/poster_card.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final overrides = [
    sessionControllerProvider
        .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    libraryApiProvider.overrideWithValue(FakeLibraryApi()),
  ];

  Future<void> pumpCards(WidgetTester tester, {List<VoidCallback>? taps}) async {
    await pumpApp(
      tester,
      Scaffold(
        body: ListView(
          key: const Key('page'),
          padding: const EdgeInsets.all(200),
          children: [
            Row(children: [
              PosterCard(
                  key: const Key('card-a'),
                  item: testItem(id: 'a', name: 'Alien'),
                  width: 160,
                  onTap: taps?[0]),
              const SizedBox(width: 400),
              PosterCard(
                  key: const Key('card-b'),
                  item: testItem(id: 'b', name: 'Heat'),
                  width: 160,
                  onTap: taps?[1]),
            ]),
            const SizedBox(height: 2000),
          ],
        ),
      ),
      overrides: overrides,
    );
  }

  Future<TestGesture> mouseOver(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    return mouse;
  }

  testWidgets('si apre dopo 500 ms di sosta, non prima', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(CardPreview), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('si chiude quando il mouse esce', (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('uscire prima dei 500 ms: niente anteprima, nessun timer',
      (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('Esc la chiude', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('dopo Esc si riapre solo quando il mouse torna sulla card',
      (tester) async {
    await pumpCards(tester);
    final card = find.byKey(const Key('card-a'));
    final mouse = await mouseOver(tester, card);
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // La card torna scoperta sotto il mouse fermo: non la riapre.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CardPreview), findsNothing);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(seconds: 1));
    await mouse.moveTo(tester.getCenter(card));
    await tester.pump(previewHoverDelay);
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('la rotella la chiude', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    final wheel = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(CardPreview))));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('da un\'anteprima a un\'altra card: si apre subito, una sola',
      (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('card-b'))));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    expect(find.text('HEAT'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('tocco: apre la scheda, niente anteprima', (tester) async {
    var taps = 0;
    await pumpCards(tester, taps: [() => taps++, () {}]);
    await tester.tap(find.byKey(const Key('card-a')));
    await tester.pump(const Duration(seconds: 1));
    expect(taps, 1);
    expect(find.byType(CardPreview), findsNothing);
  });
}
