import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/features/player/post_play.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final episode = testItem(
    id: 'e5',
    name: 'Cat in the Bag',
    kind: ItemKind.episode,
    seriesName: 'Breaking Bad',
    index: 5,
    seasonIndex: 1,
    overview: 'Walter e Jesse devono liberarsi di un corpo.',
  );

  group('PostPlayFrame', () {
    Future<ValueNotifier<bool>> pumpFrame(WidgetTester tester,
        {MotionLevel motion = MotionLevel.reduced}) async {
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      await pumpApp(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, value, _) => PostPlayFrame(
            active: value,
            child: const ColoredBox(
                key: Key('film'), color: Color(0xFF00FF00)),
          ),
        ),
        motion: motion,
      );
      return active;
    }

    testWidgets('si rimpicciolisce in alto a sinistra e torna', (tester) async {
      final active = await pumpFrame(tester, motion: MotionLevel.full);
      final full = tester.getRect(find.byKey(const Key('film')));
      expect(full, const Rect.fromLTWH(0, 0, 1440, 900));

      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.getRect(find.byKey(const Key('film')));
      expect(mid.width, inExclusiveRange(1440 * postPlayScale, 1440));
      await tester.pumpAndSettle();
      final small = tester.getRect(find.byKey(const Key('film')));
      expect(small.left, closeTo(postPlayInset, 0.01));
      expect(small.top, closeTo(postPlayInset, 0.01));
      expect(small.width, closeTo(1440 * postPlayScale, 0.01));
      expect(small.height, closeTo(900 * postPlayScale, 0.01));

      active.value = false;
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const Key('film'))), full);
    });

    testWidgets('il figlio non si rimonta passando al post-play',
        (tester) async {
      final active = await pumpFrame(tester);
      final before = tester.element(find.byKey(const Key('film')));
      active.value = true;
      await tester.pumpAndSettle();
      expect(tester.element(find.byKey(const Key('film'))), same(before));
    });
  });

  group('PostPlayLayer', () {
    testWidgets('dati del prossimo episodio e pulsanti', (tester) async {
      var played = 0;
      var credits = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: PostPlayLayer(
            episode: episode,
            countdown: true,
            paused: false,
            onPlay: () => played++,
            onWatchCredits: () => credits++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
      expect(find.text('BREAKING BAD'), findsOneWidget);
      expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
      expect(find.text('Walter e Jesse devono liberarsi di un corpo.'),
          findsOneWidget);
      expect(find.text('Riproduci ora · 10'), findsOneWidget);
      expect(find.byType(PlayNowButton), findsOneWidget);

      // Le informazioni stanno sotto il film piccolo, l'immagine a destra.
      final eyebrow = tester.getTopLeft(find.text('PROSSIMO EPISODIO'));
      expect(eyebrow.dx, closeTo(postPlayInset, 0.5));
      expect(eyebrow.dy,
          greaterThan(postPlayInset + 900 * postPlayScale));
      final image = tester.getRect(find.byKey(const Key('post-play-image')));
      expect(image.left, greaterThan(postPlayInset + 1440 * postPlayScale));
      expect(image.right, closeTo(1440 - postPlayInset, 0.5));

      await tester.tap(find.text('Guarda i titoli'));
      expect(credits, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(played, 1, reason: 'conto alla rovescia finito');
    });

    Widget layer({double textScale = 1}) => Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: PostPlayLayer(
                episode: episode,
                countdown: true,
                paused: false,
                onPlay: () {},
                onWatchCredits: () {},
              ),
            ),
          ),
        );

    for (final textScale in [1.5, 2.0]) {
      testWidgets(
          'finestra minima, testo al ${(textScale * 100).round()}%: i '
          'pulsanti restano dentro', (tester) async {
        const screen = Size(1024, 640);
        await pumpApp(tester, layer(textScale: textScale), surfaceSize: screen);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final button in [
          find.byType(PlayNowButton),
          find.byType(WfButton)
        ]) {
          final rect = tester.getRect(button);
          expect(
              rect.left >= 0 &&
                  rect.top >= 0 &&
                  rect.right <= screen.width &&
                  rect.bottom <= screen.height,
              isTrue,
              reason: '$button: $rect');
        }
        // Il nome della serie si rimpicciolisce solo come ultima difesa,
        // quando la trama ha già ceduto tutto il suo spazio.
        final title = find.text('BREAKING BAD');
        final shown = tester.getRect(title).height;
        final natural = tester.getSize(title).height;
        if (textScale <= 1.5) {
          expect(shown, closeTo(natural, 0.01));
        } else {
          expect(shown, inExclusiveRange(0, natural));
          expect(find.text('Walter e Jesse devono liberarsi di un corpo.'),
              findsNothing);
        }
      });
    }

    testWidgets("finestra molto larga: l'immagine non esce dal fondo",
        (tester) async {
      const screen = Size(2200, 640);
      await pumpApp(tester, layer(), surfaceSize: screen);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final image = tester.getRect(find.byKey(const Key('post-play-image')));
      expect(image.top, closeTo(postPlayInset, 0.5));
      expect(image.bottom, lessThanOrEqualTo(screen.height - postPlayInset));
      expect(image.width / image.height, closeTo(16 / 9, 0.01));
    });

    testWidgets('senza conto alla rovescia: "Riproduci ora"', (tester) async {
      var played = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: PostPlayLayer(
            episode: episode,
            countdown: false,
            paused: false,
            onPlay: () => played++,
            onWatchCredits: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Riproduci ora'), findsOneWidget);
      // Sul pulsante, non sull'etichetta: sopra c'è lo strato dell'onda.
      await tester.tap(find.byType(PlayNowButton));
      expect(played, 1);
    });
  });
}
