import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/landscape_card.dart';
import 'package:wonderflix/ui/media_row.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

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
}
