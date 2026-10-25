import 'dart:async';

import 'package:clock/clock.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/core/syncplay/party_mode.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';
import 'package:wonderflix/features/admin/admin_screen.dart';
import 'package:wonderflix/features/calendar/calendar_month_grid.dart';
import 'package:wonderflix/features/calendar/calendar_screen.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/match/match_actions.dart';
import 'package:wonderflix/features/match/match_column.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_screen.dart';
import 'package:wonderflix/features/match/match_swipe_deck.dart';
import 'package:wonderflix/features/requests/requests_navigation.dart';
import 'package:wonderflix/features/requests/requests_screen.dart';
import 'package:wonderflix/features/watch_party/invite_card_frame.dart';
import 'package:wonderflix/features/watch_party/party_mode_menu.dart';
import 'package:wonderflix/ui/wf_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/account/account_providers.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/quick_connect_flow.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_screen.dart';
import 'package:wonderflix/features/collections/collection_screen.dart';
import 'package:wonderflix/features/detail/detail_backdrop.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
import 'package:wonderflix/features/detail/header_parallax.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';
import 'package:wonderflix/features/person/person_screen.dart';
import 'package:wonderflix/features/profiles/profiles_screen.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/search/search_screen.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../support/admin_fakes.dart';
import '../support/fake_session_controller.dart';
import '../support/match_fakes.dart';
import '../support/requests_fakes.dart';
import '../support/watch_party_fakes.dart';
import '../support/home_fakes.dart';
import '../support/library_fakes.dart';
import '../support/profile_fakes.dart';
import '../support/pump_app.dart';
import '../support/settings_fakes.dart';
import '../support/social_fakes.dart';
import '../support/test_data.dart';

/// Quick Connect che mostra subito un errore: uno stato senza animazioni,
/// perché `pumpAndSettle` con il cerchio del codice in attesa non finisce.
class _ErrorRunner implements QuickConnectRunner {
  @override
  Stream<QcState> run() => Stream.value(QcError(Exception('no')));
}

/// Le tre misure del piano 28: telefono in verticale, in orizzontale, tablet.
const _sizes = [Size(390, 844), Size(844, 390), Size(768, 1024)];

/// Monta [screen] in modo tocco alle tre misure del telefono e verifica che
/// nessuna lasci un'eccezione (overflow compreso). Con [content] controlla
/// anche che a ogni misura il contenuto vero sia sullo schermo, non lo stato
/// di errore o di caricamento.
Future<void> expectNoOverflow(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Finder? content,
}) async {
  await pumpApp(
    tester,
    screen,
    overrides: overrides,
    surfaceSize: _sizes.first,
    touch: true,
  );
  for (final size in _sizes) {
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'a $size');
    if (content != null) {
      expect(content, findsWidgets, reason: 'contenuto assente a $size');
    }
  }
}

void main() {
  const longName =
      'Il signore degli anelli: il ritorno del re, edizione estesa';

  FakeLibraryApi libraryApi() => FakeLibraryApi()
    ..itemsById['p9'] = testItem(
      id: 'p9',
      name: 'Zendaya Maree Stoermer Coleman',
      kind: ItemKind.person,
      year: null,
      overview: List.filled(12, 'Attrice e cantante statunitense.').join(' '),
    )
    ..onItems = ((query, start, limit) => pageOf([
      for (var i = 0; i < 8; i++) testItem(id: 'm$i', name: '$longName $i'),
    ]))
    ..people = [];

  List<Override> library(FakeLibraryApi api) => [
    libraryApiProvider.overrideWithValue(api),
    requestsAvailableProvider.overrideWithValue(false),
    sessionControllerProvider.overrideWith(
      () => FakeSessionController(const SessionSignedIn(testUser)),
    ),
  ];

  List<Override> loginOverrides({required bool quickConnect}) => [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedOut())),
        quickConnectEnabledProvider.overrideWith((ref) async => quickConnect),
        quickConnectRunnerProvider.overrideWithValue(_ErrorRunner()),
        profilesProvider
            .overrideWith(() => FixedProfiles(const ProfilesState())),
      ];

  testWidgets('login: password e Quick Connect', (tester) async {
    await expectNoOverflow(tester, const LoginScreen(),
        content: find.byKey(const Key('login-submit')),
        overrides: loginOverrides(quickConnect: true));
    // Anche la scheda di Quick Connect, a misura di telefono.
    await tester.binding.setSurfaceSize(_sizes.first);
    tester.view.physicalSize = _sizes.first * tester.view.devicePixelRatio;
    await tester.tap(find.text('Quick Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Riprova'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login stretto: il logo sta sopra il pannello', (tester) async {
    await pumpApp(
      tester,
      const LoginScreen(),
      surfaceSize: const Size(390, 844),
      touch: true,
      overrides: [
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedOut()),
        ),
        quickConnectEnabledProvider.overrideWith((ref) async => false),
        profilesProvider.overrideWith(
          () => FixedProfiles(const ProfilesState()),
        ),
      ],
    );
    await tester.pumpAndSettle();
    final logo = tester.getRect(find.byType(Image));
    final panel = tester.getRect(find.byKey(const Key('login-panel')));
    expect(logo.bottom, lessThanOrEqualTo(panel.top));
    expect(logo.width, lessThanOrEqualTo(200));
    expect(panel.width, 390 - 2 * 16);
  });

  testWidgets('profili', (tester) async {
    await expectNoOverflow(
      tester,
      const ProfilesScreen(),
      content: find.text('Giulia Maria Concetta'),
      overrides: [
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionChoosingProfile()),
        ),
        profilesProvider.overrideWith(
          () => FixedProfiles(
            ProfilesState(
              book: [
                for (var i = 0; i < 5; i++)
                  testProfile(
                    userId: 'u$i',
                    name: i == 0 ? 'Giulia Maria Concetta' : 'Utente $i',
                  ),
              ].fold(const ProfileBook(), (b, p) => b.upsert(p)),
            ),
          ),
        ),
      ],
    );
  });

  testWidgets('persona', (tester) async {
    await expectNoOverflow(
      tester,
      const Scaffold(body: PersonScreen(personId: 'p9')),
      content: find.textContaining('ZENDAYA'),
      overrides: library(libraryApi()),
    );
  });

  testWidgets('catalogo film', (tester) async {
    await expectNoOverflow(
      tester,
      const Scaffold(body: CatalogScreen(kind: ItemKind.movie)),
      content: find.textContaining('FILM'),
      overrides: library(libraryApi()),
    );
  });

  testWidgets('la mia lista', (tester) async {
    final api = libraryApi()
      ..onItems = (query, start, limit) =>
          pageOf([testItem(id: 'd', name: longName)]);
    await expectNoOverflow(
      tester,
      const Scaffold(body: MyListScreen()),
      content: find.textContaining('LA MIA LISTA'),
      overrides: library(api),
    );
  });

  testWidgets('ricerca', (tester) async {
    await expectNoOverflow(
      tester,
      const Scaffold(body: SearchScreen()),
      content: find.byType(TextField),
      overrides: library(libraryApi()),
    );
  });

  testWidgets('impostazioni', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await expectNoOverflow(
      tester,
      const Scaffold(body: SettingsScreen()),
      content: find.text('Accesso come Mario'),
      overrides: [
        ...library(libraryApi()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        accountAvailableProvider.overrideWithValue(false),
        clientInfoProvider.overrideWithValue(testClientInfo),
        userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
        ...homeSettingsOverrides(),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );
  });

  /// Un film con tutto: ripresa, trailer, cast e una trama lunga.
  JellyfinItem fullMovie() => testItem(
        id: 'm1',
        name: longName,
        overview: List.filled(10, 'Frodo e Sam arrivano a Monte Fato.').join(' '),
        positionTicks: 13940000000,
        playedPercentage: 20,
        genres: ['Avventura', 'Fantasy', 'Azione'],
        rating: 8.9,
        people: [
          {'Id': 'p9', 'Name': 'Elijah Wood', 'Role': 'Frodo', 'Type': 'Actor'},
        ],
        trailers: [
          {'Url': 'https://youtube.com/watch?v=x'},
        ],
      );

  testWidgets('home', (tester) async {
    final api = libraryApi()
      ..resumeItems = [
        testItem(id: 'r1', name: longName, playedPercentage: 30),
      ];
    await expectNoOverflow(
      tester,
      const Scaffold(body: HomeScreen()),
      // Il titolo del carosello: a 844×390 le righe sono sotto il bordo.
      content: find.textContaining('IL SIGNORE DEGLI ANELLI'),
      overrides: homeOverrides(library: api),
    );
    // In verticale si vedono anche le righe.
    await tester.binding.setSurfaceSize(_sizes.first);
    tester.view.physicalSize = _sizes.first * tester.view.devicePixelRatio;
    await tester.pumpAndSettle();
    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scheda di un film', (tester) async {
    final api = libraryApi()..itemsById['m1'] = fullMovie();
    await expectNoOverflow(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
      content: find.textContaining('IL SIGNORE DEGLI ANELLI'),
      overrides: library(api),
    );
  });

  testWidgets('scheda di una serie con episodi', (tester) async {
    JellyfinItem episode(String id, int index) => testItem(
          id: id,
          name: '$longName, episodio $index',
          kind: ItemKind.episode,
          seriesId: 's1',
          seasonId: 'se1',
          seasonIndex: 1,
          index: index,
          overview: List.filled(6, 'Succede di tutto.').join(' '),
        );
    final api = libraryApi()
      ..itemsById['s1'] = testItem(
          id: 's1', name: longName, kind: ItemKind.series, childCount: 3)
      ..seasonsBySeries['s1'] = [
        for (var i = 1; i <= 3; i++)
          testItem(
              id: 'se$i', name: 'Stagione $i', kind: ItemKind.season, index: i),
      ]
      ..episodesBySeason['se1'] = [episode('e1', 1), episode('e2', 2)]
      ..nextUpItems = [episode('e1', 1)];
    await expectNoOverflow(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 's1')),
      content: find.textContaining('IL SIGNORE DEGLI ANELLI'),
      overrides: library(api),
    );
    // Gli episodi stanno sotto la testata: ci si arriva scorrendo.
    await tester.scrollUntilVisible(find.textContaining('episodio 2'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scheda stretta: tutte le azioni raggiungibili', (tester) async {
    final api = libraryApi()..itemsById['m1'] = fullMovie();
    final social = FakeSocialApi()..install(features: const {});
    social.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    social.itemRatingsById['m1'] =
        const ItemRatings(canRate: true, count: 0, friends: []);
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
      surfaceSize: _sizes.first,
      touch: true,
      overrides: [
        ...library(api),
        ...socialTestOverrides(social,
            session: false,
            features: const SocialFeatures(
                friends: true, recommendations: true, ratings: true)),
      ],
    );
    await tester.pumpAndSettle();

    // Riproduci (qui "Riprendi") a tutta larghezza meno i margini.
    final play = find.ancestor(
        of: find.text('Riprendi da 23:14'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(tester.getSize(play).width, _sizes.first.width - 2 * 16);

    // Visibile come pulsante (testo o tooltip) o come voce del menu ⋯.
    Future<void> expectReachable(String label) async {
      final shown = find.text(label).hitTestable().evaluate().isNotEmpty ||
          find.byTooltip(label).hitTestable().evaluate().isNotEmpty;
      if (shown) return;
      await tester.tap(find.byTooltip('Altre azioni'));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget, reason: '$label non si trova');
      // Chiude il menu senza scegliere.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }

    for (final label in [
      'Ricomincia',
      'Guarda insieme',
      'Trailer',
      'Aggiungi a La mia lista',
      'Segna come visto',
      'Consiglia a…',
    ]) {
      await expectReachable(label);
    }
    expect(find.byTooltip('Altre azioni'), findsOneWidget);
    // "Vota" sta nella riga dei voti degli amici, sotto la testata.
    await tester.scrollUntilVisible(find.text('Vota'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Vota'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scheda stretta: lo sfondo resta nel suo spazio, il titolo va '
      'nella barra dopo le azioni', (tester) async {
    final api = libraryApi()..itemsById['m1'] = fullMovie();
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
      surfaceSize: _sizes.first,
      touch: true,
      motion: MotionLevel.full,
      overrides: library(api),
    );
    await tester.pumpAndSettle();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final title = find.textContaining('IL SIGNORE DEGLI ANELLI');

    // Con la parallasse lo sfondo sale a metà velocità: il ritaglio lo
    // ferma al fondo del suo spazio 16:9, dove inizia il titolo.
    position.jumpTo(100);
    await tester.pump();
    final clip = tester.renderObject<RenderClipRect>(find
        .descendant(
            of: find.byType(DetailBackdrop), matching: find.byType(ClipRect))
        .first);
    expect(clip.clipper!.getClip(clip.size).bottom,
        lessThanOrEqualTo(tester.getTopLeft(title).dy + 0.5));
    // Il testo sotto l'immagine non sfuma.
    expect(
        tester
            .widgetList<Opacity>(
                find.ancestor(of: title, matching: find.byType(Opacity)))
            .every((o) => o.opacity == 1),
        isTrue);

    // Titolo nella barra solo quando il fondo della testata (le azioni) è
    // sotto la barra.
    final header = find.byType(DetailHeader);
    final key = tester.widget(header).key! as GlobalKey;
    final threshold = tester.getSize(header).height - shellCompactBarHeight;
    expect(
        barTitleVisible(threshold - 1, reduced: false, compactHeader: key),
        isFalse);
    expect(barTitleVisible(threshold, reduced: false, compactHeader: key),
        isTrue);
    position.jumpTo(threshold);
    await tester.pump();
    expect(tester.getRect(find.byTooltip('Altre azioni')).bottom,
        lessThanOrEqualTo(shellCompactBarHeight + 0.5));
  });

  testWidgets('saga', (tester) async {
    final api = libraryApi()
      ..itemsById['c1'] = testItem(
          id: 'c1',
          name: '$longName - Collezione',
          kind: ItemKind.boxSet,
          year: null,
          runtimeMinutes: null,
          overview: List.filled(8, 'Tre film nella Terra di Mezzo.').join(' '))
      ..itemsByCollection['c1'] = [
        testItem(id: 'a1', name: '$longName 1', played: true),
        testItem(
            id: 'a2',
            name: '$longName 2',
            positionTicks: 600000000,
            playedPercentage: 10),
      ];
    await expectNoOverflow(
      tester,
      const Scaffold(body: CollectionScreen(collectionId: 'c1')),
      content: find.textContaining('Riprendi "Il signore'),
      overrides: library(api),
    );
  });

  group('amministrazione', () {
    late FakeAdminApi api;
    late FakePluginAdminApi plugin;

    setUp(() {
      api = FakeAdminApi()
        ..sessionsValue = testSessions()
        ..partiesValue = testParties()
        ..librariesValue = testLibraries()
        ..tasksValue = testTasks()
        ..activityValue = testActivity();
      plugin = FakePluginAdminApi();
    });

    List<Override> admin() => adminTestOverrides(api,
        plugin: plugin,
        features: const SocialFeatures(inbox: true, account: true));

    for (final (tab, text) in [
      (AdminTab.sessions, 'In riproduzione'),
      (AdminTab.users, 'garg'),
      (AdminTab.maintenance, 'Librerie'),
      (AdminTab.activity, 'Aggiorna'),
      (AdminTab.wonderflix, 'Annuncio'),
    ]) {
      testWidgets('admin: scheda ${tab.name}', (tester) async {
        await expectNoOverflow(
          tester,
          Scaffold(body: AdminScreen(tab: tab)),
          overrides: admin(),
          content: find.text(text),
        );
        // Le righe fuori vista non sono costruite: si scorre fino in fondo.
        await tester.binding.setSurfaceSize(_sizes.first);
        tester.view.physicalSize = _sizes.first * tester.view.devicePixelRatio;
        await tester.pumpAndSettle();
        for (var i = 0; i < 40; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'scorrendo, passo $i');
        }
      });
    }

    testWidgets('admin stretto: le schede scorrono e si raggiungono tutte',
        (tester) async {
      final router = GoRouter(initialLocation: '/admin', routes: [
        GoRoute(
          path: '/admin',
          builder: (context, state) => Scaffold(
              body: AdminScreen(
                  tab: AdminTab.parse(state.uri.queryParameters['tab']))),
        ),
      ]);
      await pumpAppRouter(tester, router,
          overrides: admin(), surfaceSize: const Size(390, 844), touch: true);
      await tester.pumpAndSettle();

      final last = find.byKey(const ValueKey('admin-tab-wonderflix'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.getRect(last).right, lessThanOrEqualTo(390));
      expect(tester.getSize(last).height, greaterThanOrEqualTo(44));
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.text('Annuncio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('richieste', () {
    late FakeRequestsApi api;

    setUp(() {
      api = FakeRequestsApi()
        ..meValue = const RequestsMe(
            canRequest: true, canManage: true, hasAccount: true)
        ..lists[RequestsFilter.pending] = [
          testMediaRequest(
              id: 1,
              title: 'Dune - Parte due con un titolo molto lungo da spezzare',
              requester: 'Garg'),
        ]
        ..lists[RequestsFilter.mine] = [testMediaRequest(id: 3, title: 'Mia')];
    });

    List<Override> requests() => [
          ...requestsTestOverrides(api),
          socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
              const SocialFeatures(requests: true))),
        ];

    testWidgets('richieste', (tester) async {
      await expectNoOverflow(
        tester,
        const Scaffold(body: RequestsScreen(initialTab: RequestsTab.pending)),
        overrides: requests(),
        content: find.textContaining('Dune - Parte due'),
      );
    });

    testWidgets('richiesta stretta: Approva e Rifiuta sotto il titolo e '
        'toccabili', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: RequestsScreen(initialTab: RequestsTab.pending)),
        overrides: requests(),
        surfaceSize: const Size(390, 844),
        touch: true,
      );
      await tester.pumpAndSettle();

      final title = find.textContaining('Dune - Parte due');
      expect(title, findsOneWidget);
      expect(tester.getSize(title).width, greaterThanOrEqualTo(390 / 2));
      final decline = find.byKey(const Key('request-decline'));
      final approve = find.byType(WfButton);
      for (final button in [decline, approve]) {
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(tester.getTopLeft(button).dy,
            greaterThan(tester.getBottomLeft(title).dy));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('calendario', () {
    late FakeHomeApi api;

    setUp(() {
      api = FakeHomeApi()
        ..calendarPage = CalendarPage(
          episodes: [
            for (var d = 1; d <= 3; d++)
              testEpisode(
                  seriesName: 'The Bear con un titolo davvero molto lungo',
                  episode: d,
                  airDate: DateTime.utc(2026, 10, 12, 1)),
          ],
          movies: [testUpcomingMovie(title: 'Hope')],
        );
    });

    List<Override> calendar() => [
          homeApiProvider.overrideWithValue(api),
          socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
              const SocialFeatures(calendar: true, requests: true))),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ];

    testWidgets('calendario', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 10, 22, 12)), () async {
        await expectNoOverflow(
          tester,
          const Scaffold(body: CalendarScreen()),
          overrides: calendar(),
          content: find.text('Ottobre 2026'),
        );
      });
    });

    testWidgets('calendario a 844x390: celle alte almeno 44, la griglia '
        'scorre', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 10, 22, 12)), () async {
        await pumpApp(
          tester,
          const Scaffold(body: CalendarScreen()),
          overrides: calendar(),
          surfaceSize: const Size(844, 390),
          touch: true,
        );
        await tester.pumpAndSettle();

        expect(find.text('Ottobre 2026'), findsOneWidget);
        final cell = find.byKey(const Key('calendar-day-2026-10-12'));
        expect(tester.getSize(cell).height, greaterThanOrEqualTo(44));
        expect(
            find.descendant(
                of: find.byType(CalendarMonthGrid),
                matching: find.byType(Scrollable)),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  Future<void> pumpMatchRoom(WidgetTester tester, MatchState state) async {
    final match = FakeMatchApi();
    match.rooms['r1'] = state;
    final library = FakeLibraryApi()
      ..itemsById['m1'] = testItem(id: 'm1', name: longName)
      ..itemsById['m2'] = testItem(id: 'm2', name: 'Alien');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => unawaited(openMatchRoom(context, ref)),
              child: const Text('apri'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/match/:id',
        builder: (context, state) =>
            Scaffold(body: MatchScreen(roomId: state.pathParameters['id']!)),
      ),
    ]);
    await pumpAppRouter(
      tester,
      router,
      surfaceSize: _sizes.first,
      touch: true,
      overrides: [
        ...socialTestOverrides(FakeSocialApi(),
            events: const Stream.empty(),
            features: const SocialFeatures(
                friends: true, parties: true, match: true)),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        partyChannelApiProvider.overrideWithValue(
            FakePartyChannelApi()..install()),
        matchApiProvider.overrideWithValue(match),
        sharedPreferencesProvider.overrideWithValue(prefs),
        libraryApiProvider.overrideWithValue(library),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> expectMatchFits(WidgetTester tester, Finder content) async {
    for (final size in _sizes) {
      await tester.binding.setSurfaceSize(size);
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'a $size');
      expect(content, findsWidgets, reason: 'a $size');
    }
  }

  testWidgets('match: attesa con gli amici da invitare', (tester) async {
    await pumpMatchRoom(tester, testMatchState());
    await expectMatchFits(tester, find.byKey(const Key('match-start')));
  });

  testWidgets('match: votazione, mazzo sopra e match sotto', (tester) async {
    const mario = MatchMember(userId: 'u1', name: 'Mario', voted: 0);
    const luigi = MatchMember(userId: 'u2', name: 'Luigi', voted: 0);
    await pumpMatchRoom(
        tester,
        testMatchState(
            phase: MatchPhase.voting,
            members: const [mario, luigi],
            stack: const ['m1', 'm2'],
            matches: const ['m2']));
    await expectMatchFits(tester, find.text(longName));
    // Nello stretto il mazzo sta sopra la colonna dei match, non accanto.
    await tester.binding.setSurfaceSize(_sizes.first);
    tester.view.physicalSize = _sizes.first * tester.view.devicePixelRatio;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(MatchColumn)).dy,
        greaterThan(tester.getBottomLeft(find.byType(MatchSwipeDeck)).dy));
  });

  group('watch party', () {
    testWidgets('menu della modalità aperto', (tester) async {
      for (final size in [const Size(360, 640), const Size(844, 390)]) {
        await pumpApp(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showPartyModeMenu(context, last: PartyMode.friends),
                child: const Text('apri'),
              ),
            ),
          ),
          surfaceSize: size,
          touch: true,
        );
        await tester.tap(find.text('apri'));
        await tester.pumpAndSettle();
        final item = find.byKey(const Key('party-mode-Private'));
        expect(item, findsOneWidget, reason: '$size');
        expect(tester.getSize(item).width, lessThanOrEqualTo(size.width - 16),
            reason: '$size');
        expect(tester.takeException(), isNull, reason: '$size');
        // Un tocco fuori chiude il menu.
        await tester.tapAt(const Offset(1, 1));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('invito al party mostrato', (tester) async {
      await expectNoOverflow(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: InviteCardFrame(
              icon: Icons.group,
              title: 'Garg ti invita a guardare "$longName"',
              subtitle: 'Serata con un nome piuttosto lungo davvero',
              onDismiss: () {},
              onJoin: () {},
            ),
          ),
        ),
        content: find.textContaining('Garg ti invita'),
      );
    });
  });
}
