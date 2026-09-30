import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/landscape_card.dart';
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

  // Il pulsante play al passaggio del mouse è stato sostituito
  // dall'anteprima (spec C §7.1); i dettagli sono in
  // card_preview_host_test.dart.
  testWidgets('mouse fermo su una card: si apre l\'anteprima', (tester) async {
    await pumpApp(
      tester,
      Center(child: PosterCard(item: testItem(), width: 160)),
      overrides: [signedIn],
    );
    expect(find.byType(CardPreview), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(WfImage)));
    await tester.pump(previewHoverDelay);
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
