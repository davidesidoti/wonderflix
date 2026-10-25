import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

import '../support/fake_session_controller.dart';
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
      final shown = find.text(label).evaluate().isNotEmpty ||
          find.byTooltip(label).evaluate().isNotEmpty;
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
}
