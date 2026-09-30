import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/landscape_card.dart';
import 'package:wonderflix/ui/card_play_button.dart';
import 'package:wonderflix/ui/media_row.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/smooth_scroll.dart';
import 'package:wonderflix/ui/wf_buttons.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  testWidgets('PosterCard: titolo, anno, badge visto e tap', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Center(
        child: PosterCard(
            item: testItem(played: true), width: 160, onTap: () => taps++),
      ),
      overrides: [signedIn],
    );
    expect(find.text('Dune: Parte Due'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.byType(WatchedBadge), findsOneWidget);
    await tester.tap(find.byType(PosterCard));
    expect(taps, 1);
  });

  testWidgets('PosterCard con sorgente: Hero sulla locandina', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: PosterCard(
            item: testItem(id: 'm1'), width: 160, heroSource: 'home.latest.0'),
      ),
      overrides: [signedIn],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag,
        const WfHeroTag('m1', 'home.latest.0'));
  });

  testWidgets('PosterCard senza sorgente o con animazioni ridotte: niente Hero',
      (tester) async {
    await pumpApp(
      tester,
      Center(child: PosterCard(item: testItem(), width: 160, onTap: () {})),
      overrides: [signedIn],
      motion: MotionLevel.full,
    );
    expect(find.byType(Hero), findsNothing);
    await pumpApp(
      tester,
      Center(
        child: PosterCard(item: testItem(), width: 160, heroSource: 'x.0'),
      ),
      overrides: [signedIn],
    );
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('LandscapeCard con sorgente: Hero sull\'immagine', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: LandscapeCard(item: testItem(id: 'm1'), heroSource: 'home.resume.3'),
      ),
      overrides: [signedIn],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag,
        const WfHeroTag('m1', 'home.resume.3'));
  });

  testWidgets("card dentro una pagina: sorgente legata all'istanza",
      (tester) async {
    await pumpApp(
      tester,
      WfHeroScope(
        id: 'pagina-1',
        child: Row(children: [
          PosterCard(item: testItem(id: 'm1'), width: 160, heroSource: 'similar.0'),
          LandscapeCard(item: testItem(id: 'm2'), heroSource: 'home.resume.1'),
        ]),
      ),
      overrides: [signedIn],
      motion: MotionLevel.full,
    );
    expect(tester.widgetList<Hero>(find.byType(Hero)).map((h) => h.tag), [
      const WfHeroTag('m1', 'pagina-1|similar.0'),
      const WfHeroTag('m2', 'pagina-1|home.resume.1'),
    ]);
  });

  testWidgets('PosterCard: barra di avanzamento se iniziato', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: PosterCard(
            item: testItem(playedPercentage: 40), width: 160, onTap: () {}),
      ),
      overrides: [signedIn],
    );
    expect(find.byType(ProgressStrip), findsOneWidget);
    expect(find.byType(WatchedBadge), findsNothing);
  });

  testWidgets('LandscapeCard di un episodio', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: LandscapeCard(
          item: testItem(
            id: 'e4',
            name: 'Please Hold',
            kind: ItemKind.episode,
            seriesName: 'The Last of Us',
            index: 4,
            seasonIndex: 1,
          ),
          onTap: () {},
        ),
      ),
      overrides: [signedIn],
    );
    expect(find.text('The Last of Us'), findsOneWidget);
    expect(find.text('S1:E4 · Please Hold'), findsOneWidget);
  });

  testWidgets('MediaRow: titolo e frecce', (tester) async {
    await pumpApp(
      tester,
      MediaRow(
        title: 'Continua a guardare',
        height: 60,
        itemCount: 30,
        itemBuilder: (context, i) => SizedBox(width: 100, child: Text('i$i')),
      ),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller, isA<SmoothScrollController>());
    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(find.byKey(const Key('row-next')), findsOneWidget);
    await tester.tap(find.byKey(const Key('row-next')));
    await tester.pumpAndSettle();
    expect(find.text('i0'), findsNothing, reason: 'la riga è scorsa');
  });

  testWidgets('WfButton in una Row non va in overflow', (tester) async {
    await pumpApp(
      tester,
      Row(children: [
        WfButton.primary(label: 'Riproduci', icon: Icons.play_arrow, onPressed: () {}),
        WfButton.secondary(label: 'Trailer', icon: Icons.movie, onPressed: () {}),
      ]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Riproduci'), findsOneWidget);
  });

  group('pulsante play al passaggio del mouse', () {
    final playButton = find.byTooltip('Riproduci');

    Future<TestGesture> hoverImage(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(WfImage)));
      await tester.pumpAndSettle();
      return gesture;
    }

    Widget posterCard({VoidCallback? onTap, VoidCallback? onPlay}) => Center(
          child: PosterCard(
              item: testItem(),
              width: 160,
              onTap: onTap ?? () {},
              onPlay: onPlay),
        );

    Widget landscapeCard({VoidCallback? onTap, VoidCallback? onPlay}) => Center(
          child: LandscapeCard(
              item: testItem(), onTap: onTap ?? () {}, onPlay: onPlay),
        );

    final builders = <String, Widget Function({VoidCallback? onTap, VoidCallback? onPlay})>{
      'PosterCard': posterCard,
      'LandscapeCard': landscapeCard,
    };

    for (final entry in builders.entries) {
      testWidgets('${entry.key}: compare solo con il mouse sopra', (tester) async {
        await pumpApp(tester, entry.value(onPlay: () {}), overrides: [signedIn]);
        expect(playButton, findsNothing);
        expect(find.byType(CardPlayButton), findsNothing);

        final gesture = await hoverImage(tester);
        expect(playButton, findsOneWidget);
        expect(find.byIcon(LucideIcons.play), findsOneWidget);

        await gesture.moveTo(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(playButton, findsNothing);
      });

      testWidgets('${entry.key}: il tap sul pulsante chiama solo onPlay',
          (tester) async {
        var taps = 0;
        var plays = 0;
        await pumpApp(
          tester,
          entry.value(onTap: () => taps++, onPlay: () => plays++),
          overrides: [signedIn],
        );
        await hoverImage(tester);
        await tester.tap(playButton);
        await tester.pumpAndSettle();
        expect(plays, 1);
        expect(taps, 0);

        // Fuori dal pulsante il tap apre ancora la card.
        final image = find.byType(WfImage);
        await tester.tapAt(tester.getTopLeft(image) + const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(plays, 1);
      });

      testWidgets('${entry.key}: senza onPlay il pulsante non compare mai',
          (tester) async {
        await pumpApp(tester, entry.value(), overrides: [signedIn]);
        await hoverImage(tester);
        expect(playButton, findsNothing);
        expect(find.byType(CardPlayButton), findsNothing);
      });
    }
  });
}
