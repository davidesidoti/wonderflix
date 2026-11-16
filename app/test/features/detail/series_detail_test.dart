import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_actions_menu.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/detail/series_detail_view.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/request_seasons.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';
import 'package:wonderflix/ui/ticket_shape.dart';
import 'package:wonderflix/ui/tv_focusable.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

JellyfinItem ep(String id, String season, int seasonIndex, int index,
        {bool played = false, int position = 0, double? pct}) =>
    testItem(
      id: id,
      name: 'Episodio $index',
      kind: ItemKind.episode,
      seriesId: 's1',
      seriesName: 'The Last of Us',
      seasonId: season,
      seasonIndex: seasonIndex,
      index: index,
      runtimeMinutes: 45,
      played: played,
      positionTicks: position,
      playedPercentage: pct,
    );

void main() {
  late FakeLibraryApi api;
  late FakeDisplayPreferencesApi prefs;

  setUp(() {
    prefs = FakeDisplayPreferencesApi();
    api = FakeLibraryApi()
      ..itemsById['s1'] =
          testItem(id: 's1', name: 'The Last of Us', kind: ItemKind.series, childCount: 2)
      ..seasonsBySeries['s1'] = [
        testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.season, index: 1),
        testItem(id: 'se2', name: 'Stagione 2', kind: ItemKind.season, index: 2),
      ]
      ..episodesBySeason['se1'] = [
        ep('e3', 'se1', 1, 3, played: true),
        ep('e4', 'se1', 1, 4, position: 13940000000, pct: 50),
      ]
      ..episodesBySeason['se2'] = [ep('e21', 'se2', 2, 1)]
      ..nextUpItems = [ep('e4', 'se1', 1, 4, position: 13940000000, pct: 50)];
  });

  Future<void> pumpSeries(WidgetTester tester,
      {String? seasonId,
      MotionLevel motion = MotionLevel.reduced,
      List<Override> extra = const [],
      Size surfaceSize = const Size(1440, 900),
      bool tv = false}) async {
    await pumpApp(
        tester, Scaffold(body: ItemDetailScreen(itemId: 's1', seasonId: seasonId)),
        surfaceSize: surfaceSize,
        tv: tv,
        overrides: [
          ...extra,
          libraryApiProvider.overrideWithValue(api),
          displayPreferencesApiProvider.overrideWithValue(prefs),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
        motion: motion);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('gli episodi non si spostano quando le stagioni arrivano',
      (tester) async {
    await pumpApp(tester, Scaffold(body: ItemDetailScreen(itemId: 's1')),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          displayPreferencesApiProvider.overrideWithValue(prefs),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
        motion: MotionLevel.full);
    for (var i = 0; i < 6 && find.text('Episodio 3').evaluate().isEmpty; i++) {
      await tester.pump();
    }
    final first = tester.getTopLeft(find.text('Episodio 3'));
    // A dissolvenza finita il primo episodio sta dov'era quando è comparso.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text('Episodio 3')), first);
  });

  Future<void> scrollToTicket(WidgetTester tester) => tester.scrollUntilVisible(
      find.byKey(const Key('next-episode-ticket')), 200,
      scrollable: find
          .byWidgetPredicate((w) =>
              w is Scrollable &&
              w.axisDirection == AxisDirection.down &&
              w.physics is! NeverScrollableScrollPhysics)
          .first);

  testWidgets("serie: riga oro con l'anno", (tester) async {
    await pumpSeries(tester);
    expect(find.text('Serie · 2024'), findsOneWidget);
  });

  testWidgets('serie senza anno: la riga oro dice solo Serie', (tester) async {
    api.itemsById['s1'] = testItem(
        id: 's1',
        name: 'The Last of Us',
        kind: ItemKind.series,
        year: null,
        childCount: 2);
    await pumpSeries(tester);
    expect(find.text('Serie'), findsOneWidget);
    expect(find.textContaining('Serie ·'), findsNothing);
  });

  testWidgets('episodio: codice, data, durata e Visto prima del ⋯',
      (tester) async {
    api.episodesBySeason['se1'] = [
      testItem(
          id: 'e3',
          name: 'La scatola',
          kind: ItemKind.episode,
          seriesId: 's1',
          seasonId: 'se1',
          seasonIndex: 1,
          index: 3,
          runtimeMinutes: 52,
          premiereDate: '2025-07-27T00:00:00.0000000Z')
    ];
    await pumpSeries(tester);
    expect(find.text('La scatola'), findsOneWidget);
    expect(find.text('S1:E3 · 27 lug 2025 · 52 min'), findsOneWidget);
    final chip = find.widgetWithText(FilterChip, 'Visto');
    final more = find.byTooltip('Altre azioni').last;
    expect(tester.getCenter(chip).dx, lessThan(tester.getCenter(more).dx));
    await tester.tap(chip);
    await tester.pump();
    await tester.pump();
    expect(api.playedCalls, contains(('e3', true)));
    expect(tester.widget<FilterChip>(chip).selected, isTrue);
  });

  testWidgets('episodio senza data né durata: nessun punto in più',
      (tester) async {
    api.episodesBySeason['se1'] = [
      testItem(
          id: 'e3',
          name: 'La scatola',
          kind: ItemKind.episode,
          seriesId: 's1',
          seasonId: 'se1',
          seasonIndex: 1,
          index: 3,
          runtimeMinutes: null)
    ];
    await pumpSeries(tester);
    expect(find.text('S1:E3'), findsOneWidget);
  });

  testWidgets('prossimo episodio, stagioni ed episodi', (tester) async {
    await pumpSeries(tester);
    expect(find.text('THE LAST OF US'), findsOneWidget);
    expect(find.text('2024 · 2 stagioni'), findsOneWidget);
    expect(find.text('Riprendi S1:E4'), findsOneWidget);
    expect(find.text('Stagione 1'), findsOneWidget);
    expect(find.text('Stagione 2'), findsOneWidget);
    expect(find.text('Episodio 3'), findsOneWidget);
    expect(find.text('Episodio 4'), findsOneWidget);
    expect(api.nextUpCalls, contains('s1'));
  });

  testWidgets('il prossimo episodio è un biglietto con Prossimo e quanto manca',
      (tester) async {
    await pumpSeries(tester); // e4 iniziato a 23:14 di 45 min, è il nextUp
    final ticket = find.byKey(const Key('next-episode-ticket'));
    expect(ticket, findsOneWidget);
    expect(find.descendant(of: ticket, matching: find.text('Prossimo')),
        findsOneWidget);
    expect(
        find.descendant(
            of: ticket, matching: find.text('Riprendi · rimangono 22 min')),
        findsOneWidget);
    expect(
        find.descendant(
            of: ticket,
            matching: find.byWidgetPredicate(
                (w) => w is ClipPath && w.clipper is TicketClipper)),
        findsOneWidget);
    expect(find.descendant(of: ticket, matching: find.text('Episodio 4')),
        findsOneWidget);
    // Stesse azioni delle altre righe.
    expect(
        find.descendant(
            of: ticket, matching: find.widgetWithText(FilterChip, 'Visto')),
        findsOneWidget);
  });

  testWidgets('prossimo non iniziato: Riproduci', (tester) async {
    api.nextUpItems = [ep('e21', 'se2', 2, 1)];
    await pumpSeries(tester, seasonId: 'se2');
    final ticket = find.byKey(const Key('next-episode-ticket'));
    expect(find.descendant(of: ticket, matching: find.text('Riproduci')),
        findsOneWidget);
    expect(find.descendant(of: ticket, matching: find.textContaining('rimangono')),
        findsNothing);
  });

  testWidgets("stretto: il biglietto c'è anche lì", (tester) async {
    await pumpSeries(tester, surfaceSize: const Size(390, 780));
    expect(find.byKey(const Key('next-episode-ticket')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stretto: Visto prima del ⋯ e si tocca', (tester) async {
    await pumpSeries(tester, surfaceSize: const Size(390, 780));
    final tile = find.byWidgetPredicate(
        (w) => w is EpisodeTile && w.episode.id == 'e3');
    final chip =
        find.descendant(of: tile, matching: find.widgetWithText(FilterChip, 'Visto'));
    final more =
        find.descendant(of: tile, matching: find.byTooltip('Altre azioni'));
    expect(tester.getCenter(chip).dx, lessThan(tester.getCenter(more).dx));
    await tester.tap(chip);
    await tester.pump();
    await tester.pump();
    expect(api.playedCalls, contains(('e3', false)));
  });

  testWidgets('stretto con testo a 1,5: niente overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSeries(tester, surfaceSize: const Size(390, 780));
    await scrollToTicket(tester);
    expect(tester.takeException(), isNull);
    final chip = find.descendant(
        of: find.byKey(const Key('next-episode-ticket')),
        matching: find.widgetWithText(FilterChip, 'Visto'));
    // Lascia finire le animazioni dello scorrimento prima di toccare.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(chip);
    await tester.pump();
    await tester.pump();
    expect(api.playedCalls, contains(('e4', true)));
  });

  testWidgets('TV: episodio visto col distintivo, biglietto senza azioni',
      (tester) async {
    await pumpSeries(tester, surfaceSize: const Size(960, 540), tv: true);
    await scrollToTicket(tester);
    final watched = find.byWidgetPredicate(
        (w) => w is EpisodeTile && w.episode.id == 'e3');
    expect(find.descendant(of: watched, matching: find.byType(WatchedBadge)),
        findsOneWidget);
    final ticket = find.byKey(const Key('next-episode-ticket'));
    expect(ticket, findsOneWidget);
    expect(find.descendant(of: ticket, matching: find.byType(FilterChip)),
        findsNothing);
  });

  testWidgets('TV: col focus il biglietto ha un anello crema aderente',
      (tester) async {
    await pumpSeries(tester, surfaceSize: const Size(960, 540), tv: true);
    await scrollToTicket(tester);
    final focusable = find.descendant(
        of: find.byKey(const Key('next-episode-ticket')),
        matching: find.byType(TvFocusable));
    final shape = find
        .descendant(of: focusable, matching: find.byType(Stack))
        .first;
    Focus.of(tester.element(shape)).requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final ring = find
        .descendant(
            of: focusable,
            matching: find.byWidgetPredicate((w) =>
                w is DecoratedBox &&
                w.position == DecorationPosition.foreground))
        .first;
    final border = (tester.widget<DecoratedBox>(ring).decoration
            as BoxDecoration)
        .border! as Border;
    expect(border.top.color, WfColors.cream);
    final a = tester.getRect(ring), b = tester.getRect(shape);
    expect((a.left - b.left).abs(), lessThan(1));
    expect((a.top - b.top).abs(), lessThan(1));
    expect((a.width - b.width).abs(), lessThan(1));
    expect((a.height - b.height).abs(), lessThan(1));
  });

  testWidgets('serie: il primario dice Riprendi S1:E4 e Richiedi stagioni è '
      'nel ⋯', (tester) async {
    api.itemsById['s1'] = testItem(
        id: 's1',
        name: 'The Last of Us',
        kind: ItemKind.series,
        childCount: 2,
        tmdbId: 100088);
    await pumpSeries(tester,
        extra: [seasonsToRequestProvider.overrideWith((ref, key) => true)]);
    expect(find.text('Riprendi S1:E4'), findsOneWidget);
    // 45 min − 23:14 = 21m46s → 22 min.
    expect(find.text('rimangono 22 min'), findsOneWidget);
    expect(find.text('Richiedi stagioni'), findsNothing);
    await tester.tap(find.byTooltip('Altre azioni').first);
    await tester.pumpAndSettle();
    expect(find.text('Richiedi stagioni'), findsOneWidget);
  });

  testWidgets('cambio stagione', (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.text('Stagione 2'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Episodio 1'), findsOneWidget);
    expect(find.text('Episodio 3'), findsNothing);
  });

  testWidgets('la linea oro passa sotto la stagione scelta', (tester) async {
    await pumpSeries(tester);
    await tester.pumpAndSettle();
    final indicator = find.byKey(const Key('season-indicator'));
    expect(tester.getRect(indicator).left,
        closeTo(tester.getRect(find.text('Stagione 1')).left - 8, 1));
    await tester.tap(find.text('Stagione 2'));
    await tester.pumpAndSettle();
    expect(tester.getRect(indicator).left,
        closeTo(tester.getRect(find.text('Stagione 2')).left - 8, 1));
  });

  testWidgets('gli episodi entrano scaglionati solo cambiando stagione',
      (tester) async {
    await pumpSeries(tester, motion: MotionLevel.full);
    // Onda degli scheletri continua: niente pumpAndSettle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    StaggerGroup episodes(String seasonId) => tester.widget<StaggerGroup>(
        find.byKey(ValueKey('episodes-$seasonId')));
    // Alla prima apertura entrano con la scheda (elemento 5), non di nuovo.
    expect(episodes('se1').play, isFalse);

    await tester.tap(find.text('Stagione 2'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(episodes('se2').play, isTrue);
  });

  testWidgets('170 episodi: si costruiscono solo quelli vicini',
      (tester) async {
    api.episodesBySeason['se1'] = [
      for (var i = 1; i <= 170; i++) ep('x$i', 'se1', 1, i)
    ];
    await pumpSeries(tester);
    expect(find.byType(EpisodeTile, skipOffstage: false).evaluate().length,
        lessThan(40));
    await tester.scrollUntilVisible(find.textContaining('Episodio 170'), 600,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Episodio 170'), findsOneWidget);
  });

  testWidgets('stagione iniziale da parametro', (tester) async {
    await pumpSeries(tester, seasonId: 'se2');
    expect(find.text('Episodio 1'), findsOneWidget);
  });

  testWidgets('nessun NextUp: propone il primo episodio', (tester) async {
    api.nextUpItems = [];
    await pumpSeries(tester);
    expect(find.text('Riproduci S1:E3'), findsOneWidget);
  });

  testWidgets('menu "⋯": Togli da Prossimi episodi, poi Rimetti',
      (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.byTooltip('Altre azioni').first);
    await tester.pumpAndSettle();
    expect(find.text('Rimetti in Prossimi episodi'), findsNothing);
    await tester.tap(find.text('Togli da Prossimi episodi'));
    await tester.pumpAndSettle();
    expect(prefs.nextUpHidden, {'s1': 'e4'});
    expect(api.nextUpCalls.where((id) => id == 's1'), isNotEmpty);
    expect(find.text('Tolto da Prossimi episodi'), findsOneWidget);
    await tester.tap(find.byTooltip('Altre azioni').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rimetti in Prossimi episodi'));
    await tester.pumpAndSettle();
    expect(prefs.nextUpHidden, isEmpty);
  });

  testWidgets('menu "⋯": tolta con un altro episodio, la voce è Togli',
      (tester) async {
    prefs.nextUpHidden = {'s1': 'e3'};
    await pumpSeries(tester);
    await tester.tap(find.byTooltip('Altre azioni').first);
    await tester.pumpAndSettle();
    expect(find.text('Togli da Prossimi episodi'), findsOneWidget);
    expect(find.text('Rimetti in Prossimi episodi'), findsNothing);
  });

  testWidgets('menu "⋯" della serie: toglie da Continua a guardare '
      'l\'episodio da riprendere', (tester) async {
    await pumpSeries(tester);
    await tester.tap(find.byTooltip('Altre azioni').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Togli da Continua a guardare'));
    await tester.pumpAndSettle();
    expect(api.positionCalls, [('e4', 0)]);
    expect(api.playedCalls, isEmpty);
    expect(find.text('Tolto da Continua a guardare'), findsOneWidget);
  });

  testWidgets('menu "⋯" di un episodio: la voce solo con un punto di ripresa',
      (tester) async {
    await pumpSeries(tester);
    ItemActionsButton button(String id) => tester
        .widgetList<ItemActionsButton>(find.byType(ItemActionsButton))
        .singleWhere((button) => button.item.id == id);
    expect(button('e3').extra, isEmpty);
    expect(button('e4').extra.single.label, 'Togli da Continua a guardare');
    button('e4').extra.single.onSelected();
    await tester.pump();
    await tester.pump();
    expect(api.positionCalls, [('e4', 0)]);
    expect(button('e4').extra, isEmpty);
  });

  for (final (name, size, tv) in const [
    ('telefono', Size(390, 780), false),
    ('TV', Size(960, 540), true),
  ]) {
    testWidgets('$name: con il ⋯ vuoto niente "Altro"', (tester) async {
      // Segnalazioni spente, utente non admin, niente da riprendere.
      api.nextUpItems = [];
      await pumpSeries(tester, surfaceSize: size, tv: tv);
      // Quello della testata, più uno per ognuno dei 2 episodi fuori dalla TV.
      expect(find.text('Visto'), findsNWidgets(tv ? 1 : 3));
      expect(find.text('Altro'), findsNothing);
    });
  }

  testWidgets('stagioni con il numero di episodi, in una riga che scorre',
      (tester) async {
    api.seasonsBySeries['s1'] = [
      testItem(
          id: 'se1',
          name: 'Stagione 1',
          kind: ItemKind.season,
          index: 1,
          childCount: 8),
      testItem(
          id: 'se2',
          name: 'Stagione 2',
          kind: ItemKind.season,
          index: 2,
          childCount: 1),
    ];
    await pumpSeries(tester);
    expect(find.textContaining('8 episodi'), findsOneWidget);
    expect(find.textContaining('1 episodio'), findsOneWidget);
    expect(find.ancestor(of: find.textContaining('Stagione 1'), matching: find.byType(Wrap)),
        findsNothing);
    expect(
        find.ancestor(
            of: find.textContaining('Stagione 1'),
            matching: find.byWidgetPredicate((w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal)),
        findsOneWidget);
  });

  testWidgets('stagione senza episodi: niente "0 episodi"', (tester) async {
    api.seasonsBySeries['s1'] = [
      testItem(
          id: 'se1',
          name: 'Stagione 1',
          kind: ItemKind.season,
          index: 1,
          childCount: 0),
    ];
    await pumpSeries(tester);
    expect(find.textContaining('episodi'), findsNothing);
    expect(find.text('Stagione 1'), findsOneWidget);
  });

  group('stagioni lunghe in una riga che scorre (telefono)', () {
    const narrow = Size(390, 780);
    void twelveSeasons() => api.seasonsBySeries['s1'] = [
          for (var i = 1; i <= 12; i++)
            testItem(
                id: 'x$i',
                name: 'Stagione numero $i',
                kind: ItemKind.season,
                index: i),
        ];
    Finder strip() => find.byWidgetPredicate((w) =>
        w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
    Rect tabRect(WidgetTester t, int i) =>
        t.getRect(find.text('Stagione numero $i'));

    void expectShownUnderTab(WidgetTester t, int i) {
      final viewport = t.getRect(strip());
      final tab = tabRect(t, i);
      expect(tab.left, greaterThanOrEqualTo(viewport.left));
      expect(tab.right, lessThanOrEqualTo(viewport.right));
      final line = t.getRect(find.byKey(const Key('season-indicator')));
      expect(line.left, closeTo(tab.left - 8, 1));
      expect(line.left, greaterThanOrEqualTo(viewport.left - 1));
      expect(line.right, lessThanOrEqualTo(viewport.right + 1));
    }

    testWidgets('si apre sull\'ultima: scheda e linea sono in vista',
        (tester) async {
      twelveSeasons();
      await pumpSeries(tester, seasonId: 'x12', surfaceSize: narrow);
      await tester.pumpAndSettle();
      expectShownUnderTab(tester, 12);
    });

    testWidgets('scegliere una scheda tagliata la porta in vista',
        (tester) async {
      twelveSeasons();
      await pumpSeries(tester, surfaceSize: narrow);
      final viewport = tester.getRect(strip());
      // La prima scheda tagliata dal bordo destro.
      final i = [for (var i = 1; i <= 12; i++) i].firstWhere((i) =>
          tabRect(tester, i).right > viewport.right &&
          tabRect(tester, i).left - 8 < viewport.right - 8);
      await tester.tapAt(Offset(viewport.right - 4, tabRect(tester, i).center.dy));
      await tester.pumpAndSettle();
      expectShownUnderTab(tester, i);
    });
  });

  testWidgets('menu "⋯" della stagione: Segna la stagione come vista',
      (tester) async {
    await pumpSeries(tester);
    final episodesBefore = api.episodesCalls.where((id) => id == 'se1').length;
    final nextUpBefore = api.nextUpCalls.length;
    await tester.tap(find.byTooltip('Altre azioni').at(1)); // testata, poi stagione
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segna la stagione come vista'));
    await tester.pump();
    await tester.pump();
    expect(api.playedCalls, contains(('se1', true)));
    // Gli episodi e il prossimo da guardare si rileggono dal server.
    await tester.pumpAndSettle();
    expect(api.episodesCalls.where((id) => id == 'se1').length,
        greaterThan(episodesBefore));
    expect(api.nextUpCalls.length, greaterThan(nextUpBefore));
    await tester.tap(find.byTooltip('Altre azioni').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Segna la stagione come da vedere'), findsOneWidget);
  });

  testWidgets('stagione che non si segna: torna com\'era e lo dice',
      (tester) async {
    await pumpSeries(tester);
    api.error = Exception('boom');
    await tester.tap(find.byTooltip('Altre azioni').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segna la stagione come vista'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    api.error = null;
    await tester.tap(find.byTooltip('Altre azioni').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Segna la stagione come vista'), findsOneWidget);
    expect(find.text('Segna la stagione come da vedere'), findsNothing);
  });

  testWidgets('menu "⋯": senza episodio in Prossimi episodi nessuna voce',
      (tester) async {
    api.nextUpItems = [];
    await pumpSeries(tester);
    final header = tester
        .widgetList<ItemActionsButton>(find.byType(ItemActionsButton))
        .where((button) => button.item.id == 's1');
    expect(header, isNotEmpty);
    expect(header.every((button) => button.extra.isEmpty), isTrue);
  });
}
