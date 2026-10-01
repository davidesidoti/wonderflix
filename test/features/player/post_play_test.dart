import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/features/player/post_play.dart';

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
      await tester.tap(find.text('Riproduci ora'));
      expect(played, 1);
    });
  });
}
