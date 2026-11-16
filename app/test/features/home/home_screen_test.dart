import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/home/hero_carousel.dart';
import 'package:wonderflix/features/home/home_glow.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/features/match/match_entry.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/media_row.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/states.dart';
import 'package:wonderflix/ui/ticket_card.dart';

import '../../support/collections_fakes.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

/// Una libreria i cui "aggiunti di recente" (il carosello e le righe dei film
/// e delle serie) aspettano un cancello: il carosello arriva dopo che la Home
/// si è aperta.
class _GatedLatestLibrary extends FakeLibraryApi {
  Completer<void>? latestGate;

  @override
  Future<ItemPage> items(ItemQuery query,
      {required String userId,
      required int startIndex,
      required int limit,
      CancelToken? cancelToken}) async {
    final gate = latestGate;
    if (gate != null && !query.favoritesOnly) await gate.future;
    return super.items(query,
        userId: userId,
        startIndex: startIndex,
        limit: limit,
        cancelToken: cancelToken);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting());

  late FakeLibraryApi library;
  late FakeHomeApi home;
  late FakeDisplayPreferencesApi prefs;
  late FakeRequestsApi requests;
  late FakeCollectionsApi collections;

  setUp(() {
    library = FakeLibraryApi();
    home = FakeHomeApi();
    prefs = FakeDisplayPreferencesApi();
    requests = FakeRequestsApi();
    collections = FakeCollectionsApi();
  });

  /// Le risposte finte arrivano in pochi fotogrammi: composizione, poi
  /// righe.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> pumpHome(WidgetTester tester,
      {SocialFeatures features = SocialFeatures.none,
      double height = 1800}) async {
    await pumpApp(tester, const HomeScreen(),
        surfaceSize: Size(1440, height),
        overrides: homeOverrides(
            library: library,
            home: home,
            prefs: prefs,
            features: features,
            requests: requests,
            collections: collections));
    await settle(tester);
  }

  void someRows() => library
    ..resumeItems = [testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)]
    ..onItems = (query, start, limit) {
      if (query.favoritesOnly) return pageOf([testItem(id: 'f1', name: 'Interstellar')]);
      return query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'The Bear', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')]);
    };

  testWidgets('mostra le righe con contenuti', (tester) async {
    someRows();
    await pumpHome(tester);
    expect(find.text('Stasera'), findsOneWidget);
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
    expect(find.text('Serie aggiunte di recente'), findsOneWidget);
    expect(find.text('La mia lista'), findsOneWidget);
    expect(find.text('Oppenheimer'), findsWidgets);
    expect(find.text('Continua a guardare'), findsNothing, reason: 'in Stasera');
  });

  testWidgets('lo scheletro sta in una finestra stretta', (tester) async {
    // I preferiti non rispondono: la Home resta in caricamento.
    library.favoritesGate = Completer<void>();
    await pumpApp(tester, const HomeScreen(),
        surfaceSize: const Size(1024, 700),
        overrides: homeOverrides(library: library, home: home, prefs: prefs));
    await settle(tester);
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'il carosello legge mentre la composizione aspetta le funzioni del plugin',
      (tester) async {
    someRows();
    // Le funzioni non sono note: la composizione aspetta fino a 2 s e la
    // Home resta sullo scheletro.
    await pumpHome(tester, features: SocialFeatures.unknown);
    expect(find.byType(SkeletonBox), findsWidgets, reason: 'si compone ancora');
    expect(find.text('Stasera'), findsNothing);
    expect(
        library.itemQueries.map((query) => query.kinds),
        unorderedEquals([
          {ItemKind.movie},
          {ItemKind.series},
        ]),
        reason: 'i film e le serie del carosello partono subito, in parallelo');
  });

  testWidgets('senza carosello la prima riga inizia sotto la barra',
      (tester) async {
    library.resumeItems = [
      testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)
    ];
    await pumpHome(tester, height: 900);
    expect(tester.getTopLeft(find.text('Stasera')).dy,
        greaterThanOrEqualTo(shellBarHeight));
  });

  testWidgets('libreria vuota', (tester) async {
    await pumpHome(tester);
    expect(find.text("Qui non c'è ancora niente."), findsOneWidget);
  });

  testWidgets('errore con riprova', (tester) async {
    library.error = const ServerUnreachableException();
    await pumpHome(tester);
    expect(find.text('Riprova'), findsOneWidget);

    library.error = null;
    library.onItems = (query, start, limit) => pageOf([testItem(id: 'm1', name: 'Dune')]);
    await tester.tap(find.text('Riprova'));
    await settle(tester);
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
  });

  testWidgets('le card delle righe aprono l\'anteprima al passaggio del mouse',
      (tester) async {
    someRows();
    await pumpHome(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    for (final (cardType, play) in [
      (TicketCard, 'Riprendi'),
      (PosterCard, 'Riproduci'),
    ]) {
      final card = find.byType(cardType).first;
      expect(find.byType(CardPreview), findsNothing);
      await gesture.moveTo(tester.getCenter(card));
      await tester.pump(previewHoverDelay);
      await tester.pumpAndSettle();
      expect(find.byType(CardPreview), findsOneWidget, reason: '$cardType');
      expect(find.byTooltip(play), findsOneWidget, reason: '$cardType: $play');
      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('ordine dell\'admin e ritocchi dell\'utente', (tester) async {
    someRows();
    home.layoutRows = ['myList', 'resume', 'latestMovies'];
    prefs.prefs = const HomeUserPrefs(
        rows: ['resume', 'myList'], hidden: ['latestMovies']);
    await pumpHome(tester, features: const SocialFeatures(home: true));
    expect(tester.getTopLeft(find.text('Stasera')).dy,
        lessThan(tester.getTopLeft(find.text('La mia lista')).dy));
    expect(find.text('Film aggiunti di recente'), findsNothing);
    expect(find.text('Prossimi episodi'), findsNothing);
    expect(library.nextUpCalls, isEmpty, reason: 'riga spenta dall\'admin');
  });

  testWidgets('righe nascoste: nessuna chiamata', (tester) async {
    someRows();
    prefs.prefs = const HomeUserPrefs(hidden: ['becauseYouWatched', 'nextUp']);
    await pumpHome(tester);
    expect(library.playHistoryCalls, isEmpty);
    expect(library.nextUpCalls, isEmpty);
    expect(find.text('Stasera'), findsOneWidget);
  });

  testWidgets('una riga lenta entra dopo 1,5 s, al suo posto', (tester) async {
    someRows();
    home
      ..seriesGate = Completer<void>()
      ..series = UpcomingPage(items: [testEpisode()]);
    await pumpHome(tester, features: const SocialFeatures(upcomingSeries: true));
    expect(find.byType(SkeletonBox), findsWidgets, reason: 'si aspetta');
    expect(find.text('Stasera'), findsNothing);

    await tester.pump(homeRevealWait);
    await tester.pump();
    expect(find.text('Stasera'), findsOneWidget);
    expect(find.text('In arrivo'), findsNothing);

    home.seriesGate!.complete();
    await settle(tester);
    expect(find.text('In arrivo'), findsOneWidget);
    expect(tester.getTopLeft(find.text('In arrivo')).dy,
        greaterThan(tester.getTopLeft(find.text('Serie aggiunte di recente')).dy));
  });

  testWidgets('una riga in errore non si vede, niente Riprova', (tester) async {
    someRows();
    home.moviesError = const ServerUnreachableException();
    await pumpHome(tester, features: const SocialFeatures(upcomingMovies: true));
    expect(find.text('Stasera'), findsOneWidget);
    expect(find.text('Film in arrivo'), findsNothing);
    expect(find.text('Riprova'), findsNothing);
  });

  testWidgets('Home dell\'admin senza righe: resta il carosello', (tester) async {
    someRows();
    home.layoutRows = [];
    await pumpHome(tester, features: const SocialFeatures(home: true));
    expect(find.byType(HeroCarousel), findsOneWidget);
    expect(find.text('Film aggiunti di recente'), findsNothing);
    expect(find.text("Qui non c'è ancora niente."), findsNothing);
    expect(find.text('Riprova'), findsNothing);
  });

  testWidgets('carosello in errore ma una riga di Jellyfin c\'è: niente Riprova',
      (tester) async {
    // Film e serie recenti falliscono (carosello e due righe); riprese e
    // La mia lista rispondono: non falliscono tutte.
    library
      ..resumeItems = [testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)]
      ..onItems = (query, start, limit) {
        if (query.favoritesOnly) return pageOf([testItem(id: 'f1', name: 'Interstellar')]);
        throw const ServerUnreachableException();
      };
    await pumpHome(tester);
    expect(find.text('Riprova'), findsNothing);
    expect(find.byType(HeroCarousel), findsNothing);
    expect(find.text('Stasera'), findsOneWidget);
    expect(find.text('La mia lista'), findsOneWidget);
    expect(find.text('Film aggiunti di recente'), findsNothing);
  });

  testWidgets('Riprova: lo scheletro finché le righe non rispondono, poi entrano insieme',
      (tester) async {
    library.error = const ServerUnreachableException();
    await pumpHome(tester);
    expect(find.text('Riprova'), findsOneWidget);

    library
      ..error = null
      ..delay = const Duration(milliseconds: 500)
      ..onItems = (query, start, limit) => pageOf([testItem(id: 'm1', name: 'Dune')]);
    await tester.tap(find.text('Riprova'));
    await settle(tester);
    // Le letture sono in corso: gli errori di prima non contano.
    expect(find.text('Riprova'), findsNothing);
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.text('Film aggiunti di recente'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.text('Film aggiunti di recente'), findsOneWidget);
    expect(find.text('Serie aggiunte di recente'), findsOneWidget);
    expect(find.text('La mia lista'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> && key.value.startsWith('home-late-');
        }),
        findsNothing,
        reason: 'entrano tutte insieme, nessuna arriva dopo');
  });

  testWidgets('una riga che compare mentre scade l\'attesa non si legge due volte',
      (tester) async {
    someRows();
    // Le serie in arrivo fanno aspettare la Home; "Le mie richieste" compare
    // quando risponde /Me, nello stesso istante in cui scade l'attesa.
    home
      ..seriesGate = Completer<void>()
      ..series = UpcomingPage(items: [testEpisode()]);
    requests
      ..meGate = Completer<void>()
      ..lists[RequestsFilter.mine] = [
        testMediaRequest(id: 1, title: 'Andor', createdAt: DateTime.now()),
      ];
    await pumpHome(tester,
        features: const SocialFeatures(requests: true, upcomingSeries: true));
    expect(find.byType(SkeletonBox), findsWidgets, reason: 'si aspetta');

    requests.meGate!.complete();
    await tester.pump(homeRevealWait);
    await settle(tester);
    expect(find.text('Andor'), findsOneWidget);
    expect(requests.listLanguages, hasLength(1));
  });

  testWidgets('le righe nuove', (tester) async {
    final it = lookupAppLocalizations(const Locale('it'));
    final now = DateTime.now();
    final tomorrowNoon = DateTime(now.year, now.month, now.day + 1, 12);
    library
      ..playHistoryItems = [testItem(id: 'm9', name: 'Dune')]
      ..similarById['m9'] = [
        for (final (id, name) in [
          ('a', 'Arrival'),
          ('b', 'Sicario'),
          ('c', 'Prisoners'),
          ('d', 'Enemy'),
        ])
          testItem(id: id, name: name),
      ]
      ..playedMovieItems = [testItem(id: 'm1')]
      ..itemsById['m2'] = testItem(id: 'm2', name: 'Matrix Reloaded');
    requests.lists[RequestsFilter.mine] = [
      testMediaRequest(id: 1, title: 'Andor', status: RequestStatus.pending,
          createdAt: now),
    ];
    collections.collectionsList = [
      testCollection(id: 'c1', name: 'Matrix - Collezione', itemIds: ['m1', 'm2']),
    ];
    home
      ..series = UpcomingPage(items: [
        testEpisode(seriesName: 'The Bear', airDate: tomorrowNoon, jellyfinSeriesId: 's1'),
      ])
      ..movies = UpcomingPage(items: [testUpcomingMovie()]);

    await pumpHome(tester,
        height: 4000,
        features: const SocialFeatures(
            requests: true,
            collections: true,
            upcomingSeries: true,
            upcomingMovies: true));

    expect(find.text('Perché hai visto Dune'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Le mie richieste'), findsOneWidget);
    expect(find.text('Andor'), findsOneWidget);
    expect(find.text(it.requestsStatusPending), findsOneWidget);
    expect(find.text('Continua la saga'), findsOneWidget);
    expect(find.text('Matrix Reloaded'), findsOneWidget);
    expect(find.text('Matrix - Collezione · 1 di 2 visti'), findsOneWidget);
    // Serie e film in arrivo stanno insieme nella settimana (spec §8).
    expect(find.text('In arrivo'), findsOneWidget);
    expect(find.text('2 uscite'), findsOneWidget);
    expect(find.text('S2:E5'), findsOneWidget);
    expect(find.text('Film, in digitale'), findsOneWidget);
  });

  testWidgets('"Personalizza la Home" in fondo apre le impostazioni sulla '
      'sezione Home', (tester) async {
    someRows();
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: HomeScreen())),
      GoRoute(
          path: '/settings',
          builder: (context, state) => Text(
              'sezione ${state.uri.queryParameters['section']}')),
    ]);
    await pumpAppRouter(tester, router,
        // Alta abbastanza da avere in costruzione anche il link in fondo: la
        // lista costruisce solo quello che si vede.
        surfaceSize: const Size(1440, 3000),
        overrides: homeOverrides(library: library, home: home, prefs: prefs));
    await settle(tester);
    final link = find.byKey(const Key('home-customize'));
    await tester.ensureVisible(link);
    await tester.pump();
    await tester.tap(link);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('sezione home'), findsOneWidget);
  });

  testWidgets('"Personalizza la Home" anche nella Home vuota', (tester) async {
    await pumpHome(tester);
    expect(find.text("Qui non c'è ancora niente."), findsOneWidget);
    expect(find.byKey(const Key('home-customize')), findsOneWidget);
  });

  /// La lista verticale della Home (non lo scheletro che sta uscendo).
  ScrollPosition homeList(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(
          of: find.byKey(const Key('home-rows')),
          matching: find.byWidgetPredicate((w) =>
              w is Scrollable && w.axisDirection == AxisDirection.down)).first)
      .position;

  void fullTonight() => library
    ..resumeItems = [
      testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30),
    ]
    ..nextUpItems = [
      testItem(
          id: 'e1', name: 'Episodio', kind: ItemKind.episode, seriesId: 's9'),
    ];

  testWidgets('Stasera unisce Continua a guardare e Prossimi episodi, con '
      'Match e il dado nell\'intestazione', (tester) async {
    someRows();
    fullTonight();
    await pumpApp(tester, const HomeScreen(),
        surfaceSize: const Size(1440, 1800),
        overrides: [
          ...homeOverrides(library: library, home: home, prefs: prefs),
          matchEntryProvider.overrideWithValue(true),
        ]);
    await settle(tester);
    expect(find.text('Stasera'), findsOneWidget);
    expect(find.text('Continua a guardare'), findsNothing);
    expect(find.text('Prossimi episodi'), findsNothing);
    expect(find.text('2 da guardare'), findsOneWidget);
    final row = find.ancestor(
        of: find.text('Stasera'), matching: find.byType(MediaRow));
    for (final finder in [
      find.text('Non sai cosa scegliere?'),
      find.byKey(const Key('match-button')),
      find.byKey(const Key('tonight-button')),
    ]) {
      expect(find.descendant(of: row, matching: finder), findsOneWidget);
    }
    expect(find.byKey(const Key('tonight-button')), findsOneWidget);
    expect(find.byType(TicketCard), findsNWidgets(2));
  });

  testWidgets('senza Stasera Match e il dado stanno sopra le righe, a destra',
      (tester) async {
    library.onItems = (query, start, limit) =>
        pageOf([testItem(id: 'm1', name: 'Dune')]);
    await pumpApp(tester, const HomeScreen(),
        surfaceSize: const Size(1440, 1800),
        overrides: [
          ...homeOverrides(library: library, home: home, prefs: prefs),
          matchEntryProvider.overrideWithValue(true),
        ]);
    await settle(tester);
    expect(find.text('Stasera'), findsNothing);
    final button = find.byKey(const Key('tonight-button'));
    expect(button, findsOneWidget);
    expect(find.byKey(const Key('match-button')), findsOneWidget);
    expect(find.text('Non sai cosa scegliere?'), findsOneWidget);
    expect(
        find.descendant(of: find.byType(HeroCarousel), matching: button),
        findsNothing);
    expect(tester.getTopLeft(button).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(HeroCarousel)).dy));
    expect(tester.getTopLeft(button).dy,
        lessThan(tester.getTopLeft(find.text('Film aggiunti di recente')).dy));
    expect(tester.getTopRight(button).dx, greaterThan(1440 - 100));
  });

  testWidgets('l\'alone scorre con la pagina e resta dipinto quando il '
      'carosello è uscito', (tester) async {
    someRows();
    await pumpHome(tester, height: 900);
    final glow = find.byType(HomeGlow);
    expect(glow, findsOneWidget);
    expect(tester.getTopLeft(glow).dy,
        moreOrLessEquals(tester.getBottomLeft(find.byType(HeroCarousel)).dy));
    // Fuori dalla lista: la lista non dipinge un figlio uscito dallo
    // schermo, anche se ciò che sborda si vedrebbe ancora.
    expect(find.ancestor(of: glow, matching: find.byType(Scrollable)),
        findsNothing);
    final position = homeList(tester);
    position.jumpTo(HeroCarousel.height + 100);
    await tester.pump();
    expect(glow, findsOneWidget);
    final rect = tester.getRect(glow);
    expect(rect.top, moreOrLessEquals(-100));
    expect(rect.bottom, greaterThan(0), reason: 'ancora sullo schermo');
    expect(find.byType(HeroCarousel).hitTestable(), findsNothing,
        reason: 'il carosello è uscito');
  });

  testWidgets('rimontato, il carosello riparte dal primo e l\'alone con lui',
      (tester) async {
    someRows();
    library.onItems = (query, start, limit) => query.favoritesOnly
        ? pageOf([testItem(id: 'f1', name: 'Interstellar')])
        : query.kinds.contains(ItemKind.series)
            ? pageOf([
                testItem(id: 's1', name: 'The Bear', kind: ItemKind.series),
              ])
            : pageOf([
                testItem(id: 'm1', name: 'Dune'),
                testItem(id: 'm2', name: 'Alien'),
              ]);
    await pumpHome(tester, height: 900);
    HomeGlow glowWidget() => tester.widget<HomeGlow>(find.byType(HomeGlow));
    final firstId = glowWidget().item.id;
    await tester.tap(find.byKey(const ValueKey('hero-queue-1')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final secondId = glowWidget().item.id;
    expect(secondId, isNot(firstId));
    final position = homeList(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(find.byType(HeroCarousel), findsNothing,
        reason: 'la lista deve averlo smontato');
    position.jumpTo(0);
    await tester.pump();
    await tester.pump();
    expect(glowWidget().item.id, firstId);
  });

  testWidgets('senza titoli in evidenza niente alone', (tester) async {
    library.resumeItems = [
      testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)
    ];
    await pumpHome(tester);
    expect(find.byType(HeroCarousel), findsNothing);
    expect(find.byType(HomeGlow), findsNothing);
  });

  testWidgets('senza carosello né Stasera il dado è in cima alle righe, a '
      'destra', (tester) async {
    library.onItems = (query, start, limit) => query.favoritesOnly
        ? pageOf([testItem(id: 'f1', name: 'Interstellar')])
        : const ItemPage([], 0);
    await pumpHome(tester);
    expect(find.byType(HeroCarousel), findsNothing);
    final button = find.byKey(const Key('tonight-button'));
    expect(button, findsOneWidget);
    expect(tester.getTopRight(button).dx, greaterThan(1440 - 100));
    expect(tester.getTopLeft(button).dy,
        lessThan(tester.getTopLeft(find.text('La mia lista')).dy));
  });

  group('scheletro', () {
    Future<void> pumpSkeleton(WidgetTester tester, Size size,
        {bool tv = false}) async {
      library.favoritesGate = Completer<void>();
      await pumpApp(tester, const HomeScreen(),
          surfaceSize: size,
          tv: tv,
          overrides: homeOverrides(library: library, home: home, prefs: prefs));
      await settle(tester);
    }

    testWidgets('a 1280: carosello finto da y = 0, alto 500, a tutta larghezza',
        (tester) async {
      await pumpSkeleton(tester, const Size(1280, 800));
      final first = tester.getRect(find.byType(SkeletonBox).first);
      expect(first, const Rect.fromLTWH(0, 0, 1280, 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 390: locandine larghe 112', (tester) async {
      await pumpSkeleton(tester, const Size(390, 780));
      expect(
          tester
              .widgetList<SkeletonBox>(find.byType(SkeletonBox))
              .where((box) => box.width == 112),
          isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TV: carosello finto alto 300', (tester) async {
      await pumpSkeleton(tester, const Size(960, 540), tv: true);
      expect(tester.getSize(find.byType(SkeletonBox).first).height, 300);
      expect(tester.takeException(), isNull);
    });
  });

  for (final size in [const Size(1280, 800), const Size(390, 780)]) {
    testWidgets('nessun overflow a ${size.width.toInt()} con tutte le righe',
        (tester) async {
      someRows();
      fullTonight();
      home
        ..series = UpcomingPage(items: [testEpisode()])
        ..movies = UpcomingPage(items: [testUpcomingMovie()]);
      await pumpApp(tester, const HomeScreen(),
          surfaceSize: size,
          overrides: [
            ...homeOverrides(
                library: library,
                home: home,
                prefs: prefs,
                features: const SocialFeatures(
                    upcomingSeries: true, upcomingMovies: true)),
            matchEntryProvider.overrideWithValue(true),
          ]);
      await settle(tester);
      expect(find.text('Stasera'), findsOneWidget);
      final position = homeList(tester);
      for (var y = 0.0; y < position.maxScrollExtent; y += 400) {
        position.jumpTo(y);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'a $y');
      }
    });
  }

  testWidgets('il dado anche nella Home vuota', (tester) async {
    await pumpHome(tester);
    expect(find.text("Qui non c'è ancora niente."), findsOneWidget);
    expect(find.byKey(const Key('tonight-button')), findsOneWidget);
  });

  testWidgets('dal dado, Dettagli apre la scheda del titolo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    library.randomPages.add(pageOf([testItem(id: 'm9', name: 'Heat')]));
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: HomeScreen())),
      GoRoute(
          path: '/item/:id',
          builder: (context, state) =>
              Text('scheda ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router,
        surfaceSize: const Size(1440, 1600),
        overrides: [
          ...homeOverrides(library: library, home: home, prefs: prefs),
          sharedPreferencesProvider.overrideWithValue(shared),
        ]);
    await settle(tester);
    await tester.tap(find.byKey(const Key('tonight-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tonight-details')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('scheda m9'), findsOneWidget);
  });

  testWidgets('dal dado, Dettagli apre la scheda anche se il carosello arriva '
      'a finestra aperta e prende il posto del pulsante', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    final gated = _GatedLatestLibrary()
      ..resumeItems = [
        testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)
      ]
      ..onItems = ((query, start, limit) =>
          pageOf([testItem(id: 'm1', name: 'Dune')]))
      ..latestGate = Completer<void>()
      ..randomPages.add(pageOf([testItem(id: 'm9', name: 'Heat')]));
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: HomeScreen())),
      GoRoute(
          path: '/item/:id',
          builder: (context, state) =>
              Text('scheda ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router,
        surfaceSize: const Size(1440, 1600),
        overrides: [
          ...homeOverrides(library: gated, home: home, prefs: prefs),
          sharedPreferencesProvider.overrideWithValue(shared),
        ]);
    await settle(tester);
    // I recenti non sono arrivati: la Home si apre allo scadere dell'attesa,
    // con le righe che ci sono e il dado in cima, senza carosello.
    await tester.pump(homeRevealWait);
    await settle(tester);
    expect(find.byType(HeroCarousel), findsNothing);
    expect(find.text('Stasera'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tonight-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byKey(const Key('tonight-details')), findsOneWidget);

    // Con la finestra aperta il carosello arriva: il pulsante di prima viene
    // smontato, ma la scelta non si perde.
    gated.latestGate!.complete();
    await settle(tester);
    expect(find.byType(HeroCarousel), findsOneWidget);
    await tester.tap(find.byKey(const Key('tonight-details')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('scheda m9'), findsOneWidget);
  });
}
