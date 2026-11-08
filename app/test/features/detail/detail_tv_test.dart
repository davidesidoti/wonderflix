import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/ratings/friend_ratings_row.dart';
import 'package:wonderflix/features/ratings/rate_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/report_fakes.dart';
import '../../support/social_fakes.dart';

JellyfinItem _ep(
  String id,
  String season,
  int seasonIndex,
  int index, {
  int position = 0,
  double? pct,
}) => testItem(
  id: id,
  name: 'Episodio $index',
  kind: ItemKind.episode,
  seriesId: 's1',
  seriesName: 'The Last of Us',
  seasonId: season,
  seasonIndex: seasonIndex,
  index: index,
  runtimeMinutes: 45,
  positionTicks: position,
  playedPercentage: pct,
);

void main() {
  late FakeLibraryApi library;
  late FakeSocialApi social;

  setUp(() {
    library = FakeLibraryApi()
      ..itemsById['m1'] = testItem(
        id: 'm1',
        name: 'Dune: Parte Due',
        positionTicks: 13940000000,
        playedPercentage: 20,
        trailers: [
          {'Url': 'https://youtube.com/watch?v=x'},
        ],
      )
      ..itemsById['s1'] = testItem(
        id: 's1',
        name: 'The Last of Us',
        kind: ItemKind.series,
        childCount: 2,
      )
      ..seasonsBySeries['s1'] = [
        testItem(
          id: 'se1',
          name: 'Stagione 1',
          kind: ItemKind.season,
          index: 1,
        ),
        testItem(
          id: 'se2',
          name: 'Stagione 2',
          kind: ItemKind.season,
          index: 2,
        ),
      ]
      ..episodesBySeason['se1'] = [
        _ep('e3', 'se1', 1, 3),
        _ep('e4', 'se1', 1, 4, position: 13940000000, pct: 50),
      ]
      ..episodesBySeason['se2'] = [_ep('e21', 'se2', 2, 1)]
      ..nextUpItems = [_ep('e4', 'se1', 1, 4, position: 13940000000, pct: 50)];
    social = FakeSocialApi()..install(features: const {});
    social.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    social.itemRatingsById['m1'] = const ItemRatings(
      canRate: true,
      count: 0,
      friends: [],
      mine: MyRating(score: 8),
    );
  });

  Future<void> pumpDetail(
    WidgetTester tester,
    String id, {
    List<Override> extra = const [],
    Size surfaceSize = const Size(1440, 900),
  }) async {
    await pumpAppRouter(
      tester,
      GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                Scaffold(body: ItemDetailScreen(itemId: id)),
          ),
          GoRoute(
            path: '/play/:id',
            builder: (context, state) =>
                Text('player ${state.pathParameters['id']}'),
          ),
        ],
      ),
      tv: true,
      surfaceSize: surfaceSize,
      overrides: [
        ...extra,
        libraryApiProvider.overrideWithValue(library),
        ...reportTestOverrides(),
        ...socialTestOverrides(
          social,
          features: const SocialFeatures(
            friends: true,
            recommendations: true,
            ratings: true,
            reports: true,
          ),
          session: false,
        ),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(
            const SessionSignedIn(
              JellyfinUser(
                id: 'u1',
                name: 'Mario',
                isAdministrator: true,
                enableSubtitleManagement: true,
              ),
            ),
          ),
        ),
      ],
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  /// Il centro di [finder] sta dentro l'elemento col focus.
  bool hasFocus(WidgetTester tester, Finder finder) =>
      FocusManager.instance.primaryFocus?.rect.contains(
        tester.getCenter(finder.first),
      ) ??
      false;

  // Lo schermo del Fire Stick (1080p a densità 2): largo meno di 1024, ma la
  // scheda è quella larga, con i dati e i pulsanti sopra lo sfondo.
  for (final id in ['m1', 's1']) {
    testWidgets('$id a 960×540: dati e pulsanti nella prima schermata', (
      tester,
    ) async {
      final long = 'Una trama lunga che va su più righe. ' * 12;
      library.itemsById[id] = testItem(
        id: id,
        name: library.itemsById[id]!.name,
        kind: library.itemsById[id]!.kind,
        childCount: library.itemsById[id]!.childCount,
        positionTicks: 13940000000,
        playedPercentage: 20,
        overview: long,
        genres: const ['Fantascienza', 'Avventura', 'Dramma'],
        rating: 8.4,
      );
      await pumpDetail(tester, id, surfaceSize: const Size(960, 540));
      await tester.pumpAndSettle();

      const screen = Rect.fromLTWH(0, 0, 960, 540);
      bool inside(Finder f) {
        final r = tester.getRect(f.first);
        return r.top >= screen.top &&
            r.bottom <= screen.bottom &&
            r.left >= screen.left &&
            r.right <= screen.right;
      }

      final play = id == 'm1' ? 'Riprendi da 23:14' : 'Riprendi S1:E4 · 23:14';
      expect(inside(find.text(play)), isTrue, reason: play);
      expect(hasFocus(tester, find.text(play)), isTrue);
      for (final tooltip in ['Segna come visto', 'Altre azioni']) {
        expect(inside(find.byTooltip(tooltip)), isTrue, reason: tooltip);
      }
      expect(inside(find.text(long)), isTrue);
      // Nessuno scroll per arrivarci.
      final list = tester.widget<Scrollable>(find.byType(Scrollable).first);
      expect(list.controller?.offset ?? 0, 0);
    });
  }

  testWidgets('film: Giù scende fino al cast e ai simili, Su torna su', (
    tester,
  ) async {
    library
      ..itemsById['m1'] = testItem(
        id: 'm1',
        name: 'Dune: Parte Due',
        people: [
          {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
        ],
      )
      ..similarItems = [testItem(id: 'm2', name: 'Arrival')];
    await pumpDetail(tester, 'm1', surfaceSize: const Size(960, 540));
    await tester.pumpAndSettle();
    Future<void> key(LogicalKeyboardKey k) async {
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
    }

    // Le righe sotto lo schermo non sono ancora costruite; il nome sta
    // appena sotto la foto o la locandina che ha il focus.
    bool focused(Finder f) =>
        f.evaluate().isNotEmpty &&
        (FocusManager.instance.primaryFocus?.rect
                .inflate(24)
                .contains(tester.getCenter(f)) ??
            false);

    // Tra i pulsanti e il cast c'è la riga dei voti degli amici.
    Future<void> downTo(Finder f) async {
      for (var i = 0; i < 3 && !focused(f); i++) {
        await key(LogicalKeyboardKey.arrowDown);
      }
      expect(focused(f), isTrue, reason: '$f');
      // Chi ha il focus si vede.
      expect(tester.getCenter(f).dy, inInclusiveRange(0, 540), reason: '$f');
    }

    await downTo(find.text('Zendaya'));
    await downTo(find.text('Arrival'));
    await key(LogicalKeyboardKey.arrowUp);
    expect(focused(find.text('Zendaya')), isTrue);
    for (var i = 0; i < 2; i++) {
      await key(LogicalKeyboardKey.arrowUp);
    }
    expect(hasFocus(tester, find.text('Riproduci')), isTrue);
    // Tornati ai pulsanti la scheda torna in cima, alla prima schermata
    // (scorsa, la testata sfuma e i pulsanti non si vedrebbero).
    final list = tester.widget<Scrollable>(find.byType(Scrollable).first);
    expect(list.controller?.offset, 0);
  });

  testWidgets("film: il pulsante principale ha il focus all'apertura", (
    tester,
  ) async {
    await pumpDetail(tester, 'm1');
    expect(hasFocus(tester, find.text('Riprendi da 23:14')), isTrue);
  });

  testWidgets(
    'film: la riga delle azioni, in ordine, senza Insieme e Trailer',
    (tester) async {
      await pumpDetail(tester, 'm1');
      final xs = [
        for (final tooltip in [
          'Aggiungi a La mia lista',
          'Vota',
          'Consiglia a…',
          'Segna come visto',
          'Altre azioni',
        ])
          tester.getCenter(find.byTooltip(tooltip).first).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(xs.toSet(), hasLength(5));
      expect(find.text('Ricomincia'), findsOneWidget);
      expect(find.text('Trailer'), findsNothing);
      expect(find.text('Guarda insieme'), findsNothing);
    },
  );

  testWidgets('film: "Vota" apre il pannello col voto attuale', (tester) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Vota'));
    await tester.pump();
    final subject = ProviderScope.containerOf(
      tester.element(find.byType(ItemDetailScreen)),
    ).read(rateSubjectProvider);
    expect(subject?.item.id, 'm1');
    expect(subject?.title, 'Dune: Parte Due');
    expect(subject?.mine?.score, 8);
  });

  testWidgets('film: il menu Altro ha solo Info tecniche e Segnala', (
    tester,
  ) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Info tecniche'), findsOneWidget);
    expect(find.text('Segnala un problema'), findsOneWidget);
    expect(find.text('Sottotitoli…'), findsNothing);
    expect(find.text('Modifica metadati'), findsNothing);
    expect(find.text('Identifica'), findsNothing);
  });

  testWidgets('serie: focus sul principale, Giù alle stagioni, OK le sceglie, '
      'OK su un episodio lo riproduce', (tester) async {
    await pumpDetail(tester, 's1');
    expect(hasFocus(tester, find.text('Riprendi S1:E4 · 23:14')), isTrue);
    // Niente "⋯" né sulla stagione né sugli episodi: resta quello della testata.
    expect(find.byTooltip('Altre azioni'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // Giù cade sulla scheda sotto il pulsante (la geometria decide quale):
    // con Sinistra e Destra si arriva a "Stagione 2".
    final tab1 = hasFocus(tester, find.text('Stagione 1'));
    expect(tab1 || hasFocus(tester, find.text('Stagione 2')), isTrue);
    if (tab1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(hasFocus(tester, find.text('Stagione 2')), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(find.text('1. Episodio 1'), findsOneWidget);
    expect(find.text('3. Episodio 3'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(hasFocus(tester, find.text('1. Episodio 1')), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('player e21'), findsOneWidget);
  });

  testWidgets('serie: Vota vota la stagione mostrata e segue le schede', (
    tester,
  ) async {
    social.itemRatingsById['se1'] = const ItemRatings(
      canRate: true,
      count: 0,
      friends: [],
      mine: MyRating(score: 7),
    );
    social.itemRatingsById['se2'] = const ItemRatings(
      canRate: true,
      count: 0,
      friends: [],
    );
    await pumpDetail(tester, 's1');
    RateSubject? subject() => ProviderScope.containerOf(
      tester.element(find.byType(ItemDetailScreen)),
    ).read(rateSubjectProvider);

    await tester.tap(find.byTooltip('Vota'));
    await tester.pump();
    expect(subject()?.item.id, 'se1');
    expect(subject()?.title, 'The Last of Us · Stagione 1');
    expect(subject()?.mine?.score, 7);

    await tester.tap(find.text('Stagione 2'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.tap(find.byTooltip('Vota'));
    await tester.pump();
    expect(subject()?.item.id, 'se2');
    expect(subject()?.title, 'The Last of Us · Stagione 2');
    expect(subject()?.mine, isNull);
  });

  testWidgets('serie: con i voti in errore Vota non c\'è', (tester) async {
    await pumpDetail(
      tester,
      's1',
      extra: [
        itemRatingsProvider.overrideWith(
          (ref, id) async => throw StateError('voti'),
        ),
      ],
    );
    expect(find.byTooltip('Vota'), findsNothing);
  });
}
