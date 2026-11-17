import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/wf_image.dart';

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

  const identity = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ]);
  ColorFilter posterFilter(WidgetTester tester) =>
      tester.widget<ColorFiltered>(find.byType(ColorFiltered)).colorFilter;

  testWidgets('film visto: locandina spenta, solo nel catalogo',
      (tester) async {
    await pumpCard(tester, testItem(played: true));
    expect(posterFilter(tester), isNot(identity));
    await pumpCard(tester, testItem());
    expect(posterFilter(tester), identity);
    await pumpCard(tester, testItem(played: true), catalogStyle: false);
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('film visto: il mouse sopra riaccende la locandina',
      (tester) async {
    await pumpCard(tester, testItem(played: true));
    final dim = posterFilter(tester);
    final image = find.byType(WfImage);
    final before = tester.element(image);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(image));
    await tester.pump();
    expect(posterFilter(tester), identity);
    expect(posterFilter(tester), isNot(dim));
    // Lo stesso elemento: l'immagine non viene rimontata.
    expect(tester.element(image), same(before));
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(posterFilter(tester), dim);
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

  for (final scale in [1.0, 1.3]) {
    testWidgets('la card del catalogo con tre righe non va in overflow '
        '(testo ${scale}x)', (tester) async {
      await pumpApp(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: 180,
                height: catalogCellExtent(180, TextScaler.linear(scale)),
                child: PosterCard(
                    item: testItem(
                        kind: ItemKind.series,
                        name: 'Un titolo molto lungo ' * 4,
                        unplayedCount: 5,
                        status: 'Continuing'),
                    catalogStyle: true),
              ),
            ),
          ),
        ),
        overrides: [signedIn],
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('catalogColumnCount: colonne come la griglia del catalogo', () {
    expect(catalogColumnCount(358), 2); // telefono 390 - 32
    expect(catalogColumnCount(1216), 7); // 1280 - 64
    expect(catalogColumnCount(0), 1);
  });

  test('catalogCellExtent: con estensione 0 non divide per zero', () {
    expect(catalogCellExtent(0, TextScaler.noScaling).isFinite, isTrue);
  });

  test('catalogCellExtent: stesse colonne di Flutter, anche a 1170 px', () {
    // Flutter: ceil(extent / (180 + 16)). 1170 -> 6 colonne da 181,7 px.
    const scaler = TextScaler.noScaling;
    final cell = catalogCellExtent(1170, scaler);
    expect(cell, closeTo((1170 - 5 * 16) / 6 * 1.5 + 84, 0.01));
    final delegate = const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180, crossAxisSpacing: 16);
    final layout = delegate.getLayout(SliverConstraints(
        axisDirection: AxisDirection.down,
        growthDirection: GrowthDirection.forward,
        userScrollDirection: ScrollDirection.idle,
        scrollOffset: 0,
        precedingScrollExtent: 0,
        overlap: 0,
        remainingPaintExtent: 900,
        crossAxisExtent: 1170,
        crossAxisDirection: AxisDirection.right,
        viewportMainAxisExtent: 900,
        remainingCacheExtent: 900,
        cacheOrigin: 0));
    expect((layout as SliverGridRegularTileLayout).crossAxisCount, 6);
  });
}
