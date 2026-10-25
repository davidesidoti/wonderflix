import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
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

  late List<String> calls;
  setUp(() => calls = []);

  Future<void> pumpCard(WidgetTester tester, {required bool touch}) => pumpApp(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: PosterCard(
              key: const Key('card'),
              item: testItem(id: 'a', name: 'Alien'),
              width: 160,
              onTap: () => calls.add('tap'),
              previewExtra: CardPreviewExtra(
                notes: const ['Da Luca'],
                dismissTooltip: 'Non mi interessa',
                onDismiss: () => calls.add('dismiss'),
              ),
            ),
          ),
        ),
        overrides: overrides,
        touch: touch,
      );

  testWidgets(
      'tocco: pressione lunga su una card apre l anteprima dal basso con la × '
      'dei consigli', (tester) async {
    await pumpCard(tester, touch: true);
    await tester.longPress(find.byKey(const Key('card')));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getRect(find.byType(CardPreview)).bottom,
        greaterThan(screen.height - 100),
        reason: 'sta in basso');
    expect(find.text('Da Luca'), findsOneWidget);
    await tester.tap(find.byTooltip('Non mi interessa'));
    await tester.pumpAndSettle();
    expect(calls, ['dismiss']);
    expect(find.byType(CardPreview), findsNothing, reason: 'l azione chiude');
  });

  testWidgets('tocco: un tocco apre la scheda e nessuna anteprima',
      (tester) async {
    await pumpCard(tester, touch: true);
    await tester.tap(find.byKey(const Key('card')));
    await tester.pumpAndSettle();
    expect(calls, ['tap']);
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('mouse: la pressione lunga non apre il foglio', (tester) async {
    await pumpCard(tester, touch: false);
    await tester.longPress(find.byKey(const Key('card')));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('tocco: niente bordo oro rimasto acceso dopo un tocco su una card',
      (tester) async {
    await pumpCard(tester, touch: true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('card'))));
    await tester.tap(find.byKey(const Key('card')));
    await tester.pumpAndSettle();
    final border = (tester
            .widget<AnimatedContainer>(find.descendant(
                of: find.byKey(const Key('card')),
                matching: find.byType(AnimatedContainer)))
            .decoration as BoxDecoration)
        .border as Border;
    expect(border.top.color, isNot(WfColors.gold));
  });
}
