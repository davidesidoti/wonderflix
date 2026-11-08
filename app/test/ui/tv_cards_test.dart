import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/landscape_card.dart';
import 'package:wonderflix/ui/media_row.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/remote_image_card.dart';
import 'package:wonderflix/ui/tv_focusable.dart';
import 'package:wonderflix/ui/form_factor.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  Future<void> pumpRow(
    WidgetTester tester,
    Widget Function(int i, VoidCallback onTap, bool autofocus) card, {
    required List<int> taps,
    bool tv = true,
  }) =>
      pumpApp(
        tester,
        FormFactorScope(
          tv: tv,
          child: Scaffold(
            body: MediaRow(
              title: 'Riga',
              height: 300,
              itemCount: 8,
              itemBuilder: (context, i) =>
                  card(i, () => taps.add(i), i == 0),
            ),
          ),
        ),
        overrides: [signedIn],
      );

  Future<void> pressRight(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
  }

  PosterCard poster(int i, VoidCallback onTap, bool autofocus) => PosterCard(
      item: testItem(id: 'p$i', name: 'Titolo $i'),
      width: 160,
      onTap: onTap,
      autofocus: autofocus);

  testWidgets('PosterCard: DPAD destra sposta il focus, OK apre', (tester) async {
    final taps = <int>[];
    await pumpRow(tester, poster, taps: taps);
    await pressRight(tester, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, [3]);
  });

  testWidgets('PosterCard: il focus mostra il bordo oro', (tester) async {
    await pumpRow(tester, poster, taps: []);
    final focused = tester.widget<AnimatedScale>(find
        .descendant(
            of: find.byType(PosterCard).first,
            matching: find.byType(AnimatedScale))
        .first);
    expect(focused.scale, tvFocusScale);
  });

  testWidgets('il bordo ingrandito della prima card non esce dalla lista',
      (tester) async {
    await pumpRow(tester, poster, taps: []);
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byType(ListView));
    final image = tester.getRect(find
        .descendant(
            of: find.byType(PosterCard).first,
            matching: find.byType(AspectRatio))
        .first);
    expect(image.top, greaterThanOrEqualTo(list.top));
    expect(image.left, greaterThanOrEqualTo(list.left));
  });

  testWidgets('sulla TV: niente frecce di riga né anteprima', (tester) async {
    await pumpRow(tester, poster, taps: []);
    expect(find.byKey(const Key('row-previous')), findsNothing);
    expect(find.byKey(const Key('row-next')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CardPreview), findsNothing);
    // Nemmeno col mouse sopra.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(PosterCard).at(1)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('fuori dalla TV: le frecce di riga ci sono', (tester) async {
    await pumpRow(tester, poster, taps: [], tv: false);
    expect(find.byKey(const Key('row-previous')), findsOneWidget);
    expect(find.byKey(const Key('row-next')), findsOneWidget);
  });

  testWidgets('LandscapeCard: DPAD destra e OK', (tester) async {
    final taps = <int>[];
    await pumpRow(
      tester,
      (i, onTap, autofocus) => LandscapeCard(
          item: testItem(id: 'l$i', name: 'Ep $i'),
          width: 200,
          onTap: onTap,
          autofocus: autofocus),
      taps: taps,
    );
    await pressRight(tester, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, [2]);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('RemoteImageCard: DPAD destra e OK; senza onTap non si focalizza',
      (tester) async {
    final taps = <int>[];
    await pumpRow(
      tester,
      (i, onTap, autofocus) => RemoteImageCard(
          shape: RemoteCardShape.poster,
          image: null,
          title: 'R$i',
          onTap: i == 2 ? null : onTap,
          autofocus: autofocus),
      taps: taps,
    );
    await pressRight(tester, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, [1]);
    // La terza non ha onTap: il focus salta alla quarta.
    await pressRight(tester, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, [1, 3]);
  });

  group('card col focus ricostruita', () {
    /// Una riga di pulsanti con chiave per titolo: cambiando i titoli le
    /// card si ricreano, come quelle di "Consigliati per te".
    Future<ValueNotifier<List<String>>> pumpTitles(
        WidgetTester tester, List<String> titles,
        {required bool tv}) async {
      final shown = ValueNotifier(titles);
      addTearDown(shown.dispose);
      await pumpApp(
        tester,
        FormFactorScope(
          tv: tv,
          child: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: shown,
              builder: (context, titles, _) => MediaRow(
                title: 'Riga',
                height: 100,
                itemCount: titles.length,
                itemBuilder: (context, i) => TextButton(
                  key: ValueKey(titles[i]),
                  onPressed: () {},
                  child: Text(titles[i]),
                ),
              ),
            ),
          ),
        ),
        overrides: [signedIn],
      );
      return shown;
    }

    void focus(WidgetTester tester, String title) =>
        Focus.of(tester.element(find.text(title))).requestFocus();

    bool focused(WidgetTester tester, String title) =>
        Focus.of(tester.element(find.text(title))).hasPrimaryFocus;

    testWidgets('TV: il focus va alla card nello stesso posto',
        (tester) async {
      final shown = await pumpTitles(tester, ['a', 'b', 'c'], tv: true);
      focus(tester, 'b');
      await tester.pump();
      shown.value = ['x', 'y', 'z'];
      await tester.pump();
      await tester.pump();
      expect(focused(tester, 'y'), isTrue);
    });

    testWidgets('TV: se la riga si accorcia, all\'ultima card',
        (tester) async {
      final shown = await pumpTitles(tester, ['a', 'b', 'c'], tv: true);
      focus(tester, 'c');
      await tester.pump();
      shown.value = ['p', 'q'];
      await tester.pump();
      await tester.pump();
      expect(focused(tester, 'q'), isTrue);
    });

    testWidgets('fuori dalla TV il focus non si sposta da solo',
        (tester) async {
      final shown = await pumpTitles(tester, ['a', 'b', 'c'], tv: false);
      focus(tester, 'b');
      await tester.pump();
      shown.value = ['x', 'y', 'z'];
      await tester.pump();
      await tester.pump();
      expect(focused(tester, 'y'), isFalse);
    });
  });
}
