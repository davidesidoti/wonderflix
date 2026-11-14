import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/poster_card.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  Future<void> pumpCard(WidgetTester tester, JellyfinItem item,
      {bool catalogStyle = true}) {
    return pumpApp(
      tester,
      Center(
          child: PosterCard(
              item: item, width: 160, catalogStyle: catalogStyle)),
      overrides: [signedIn],
    );
  }

  JellyfinItem series({
    int? unplayed,
    bool played = false,
    String? status,
    String? endDate,
    int? year = 2008,
  }) =>
      testItem(
          kind: ItemKind.series,
          name: 'Breaking Bad',
          year: year,
          unplayedCount: unplayed,
          played: played,
          status: status,
          endDate: endDate);

  testWidgets('serie in corso: "In corso" e gli episodi da vedere, senza numero',
      (tester) async {
    await pumpCard(tester, series(unplayed: 5, status: 'Continuing'));
    expect(find.text('In corso'), findsOneWidget);
    expect(find.text('5 episodi da vedere'), findsOneWidget);
    expect(find.byType(CountBadge), findsNothing);
  });

  testWidgets('serie conclusa e vista tutta: anni e "Vista tutta"',
      (tester) async {
    await pumpCard(
        tester,
        series(
            played: true,
            unplayed: 0,
            status: 'Ended',
            endDate: '2013-09-29T00:00:00.0000000Z'));
    expect(find.text('2008–2013'), findsOneWidget);
    expect(find.text('Vista tutta'), findsOneWidget);
    expect(find.byType(WatchedBadge), findsOneWidget);
  });

  testWidgets('serie senza data di fine: solo l\'anno d\'inizio',
      (tester) async {
    await pumpCard(tester, series(year: 2022, unplayed: 1));
    expect(find.text('2022'), findsOneWidget);
    expect(find.text('1 episodio da vedere'), findsOneWidget);
  });

  testWidgets('film: anno e voto con una cifra', (tester) async {
    await pumpCard(tester, testItem(rating: 8.46));
    expect(find.text('2024  ★ 8.5'), findsOneWidget);
    await pumpCard(tester, testItem());
    expect(find.text('2024'), findsOneWidget);
  });

  testWidgets('film visto: locandina un po\' spenta, solo nel catalogo',
      (tester) async {
    await pumpCard(tester, testItem(played: true));
    expect(find.byType(ColorFiltered), findsOneWidget);
    await pumpCard(tester, testItem(played: true), catalogStyle: false);
    expect(find.byType(ColorFiltered), findsNothing);
    await pumpCard(tester, testItem());
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('titolo su due righe nel catalogo, su una altrove',
      (tester) async {
    await pumpCard(tester, testItem(name: 'Un titolo molto lungo ' * 4));
    expect(tester.widget<Text>(find.textContaining('Un titolo')).maxLines, 2);
    await pumpCard(tester, testItem(name: 'Un titolo molto lungo ' * 4),
        catalogStyle: false);
    expect(tester.widget<Text>(find.textContaining('Un titolo')).maxLines, 1);
  });

  testWidgets('catalogStyle: false lascia il conteggio e le righe di oggi',
      (tester) async {
    await pumpCard(tester, series(unplayed: 5, status: 'Continuing'),
        catalogStyle: false);
    expect(find.byType(CountBadge), findsOneWidget);
    expect(find.text('2008'), findsOneWidget);
    expect(find.text('In corso'), findsNothing);
  });

  testWidgets('la card del catalogo con tre righe non va in overflow',
      (tester) async {
    await pumpApp(
      tester,
      Center(
        child: SizedBox(
          width: 180,
          height: 270 + catalogCardTextHeight,
          child: PosterCard(
              item: testItem(
                  kind: ItemKind.series,
                  name: 'Un titolo molto lungo ' * 4,
                  unplayedCount: 5,
                  status: 'Continuing'),
              catalogStyle: true),
        ),
      ),
      overrides: [signedIn],
    );
    expect(tester.takeException(), isNull);
  });
}
