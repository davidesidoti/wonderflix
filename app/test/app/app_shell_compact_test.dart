import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/page_transitions.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/social_fakes.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

const _phone = Size(390, 844);
const _phoneLandscape = Size(844, 390);
const _desktop = Size(1440, 900);

/// Dentro un watch party.
class _InParty extends WatchPartySession {
  @override
  WatchPartyState build() =>
      const WatchPartyState(phase: WatchPartyPhase.inGroup);
}

/// Shell con un vero `GoRouter` come in `router.dart`, pagine finte e la
/// pagina-pannello Amici vera.
GoRouter _router() {
  GoRoute fake(String path) => GoRoute(
      path: path,
      pageBuilder: (context, state) =>
          shellPage(context, state, Text('pagina $path'), underBar: true));
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: appShellBuilder,
        routes: [
          for (final path in [
            '/home',
            '/movies',
            '/series',
            '/mylist',
            '/requests',
            '/calendar',
            '/search',
            '/settings',
            '/admin',
          ])
            fake(path),
          GoRoute(
              path: '/friends',
              pageBuilder: (context, state) => shellPage(
                  context,
                  state,
                  const ShellPanelPage(
                      panel: ShellPanel.friends, child: FriendsPanel()),
                  underBar: true)),
        ],
      ),
    ],
  );
}

void main() {
  late FakeSocialApi api;

  setUp(() => api = FakeSocialApi());

  Future<GoRouter> pumpShell(
    WidgetTester tester, {
    Size size = _phone,
    SocialFeatures features = const SocialFeatures(friends: true),
    JellyfinUser user = testUser,
    bool touch = true,
    List<GroupInfo> groups = const [],
    bool inParty = false,
  }) async {
    final router = _router();
    await pumpAppRouter(
      tester,
      router,
      surfaceSize: size,
      touch: touch,
      overrides: [
        ...socialTestOverrides(api, features: features, session: false),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(SessionSignedIn(user))),
        // Nessun elenco dei watch party (né timer).
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory(groups)),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        if (inParty) watchPartySessionProvider.overrideWith(_InParty.new),
      ],
    );
    await tester.pumpAndSettle();
    return router;
  }

  // La pagina in cima, anche dopo un push (come la riceve la shell).
  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  testWidgets('stretto: barra in basso con Home, Cerca, La mia lista, Altro',
      (tester) async {
    await pumpShell(tester);

    for (final route in ['/home', '/search', '/mylist', '/more']) {
      expect(find.byKey(Key('bottom-nav-$route')), findsOneWidget,
          reason: route);
      expect(tester.getSize(find.byKey(Key('bottom-nav-$route'))).height,
          greaterThanOrEqualTo(44));
    }
    expect(find.byKey(const Key('bottom-nav-/requests')), findsNothing);
    expect(find.byKey(const Key('nav-/movies')), findsNothing);
    // L'avatar senza nome.
    expect(find.byKey(const Key('user-menu')), findsOneWidget);
    expect(find.text('Mario'), findsNothing);
  });

  testWidgets('stretto: Richieste in basso quando ci sono', (tester) async {
    await pumpShell(tester,
        features: const SocialFeatures(friends: true, requests: true));

    expect(find.byKey(const Key('bottom-nav-/requests')), findsOneWidget);
  });

  testWidgets('stretto: le voci della barra in basso navigano',
      (tester) async {
    final router = await pumpShell(tester);

    await tester.tap(find.byKey(const Key('bottom-nav-/search')));
    await tester.pumpAndSettle();
    expect(location(router), '/search');
    expect(find.text('pagina /search'), findsOneWidget);
  });

  testWidgets(
      'Altro apre Film, Serie, Impostazioni, Cambia profilo, Esci; Admin '
      'solo per gli admin', (tester) async {
    final router = await pumpShell(tester);

    await tester.tap(find.byKey(const Key('bottom-nav-/more')));
    await tester.pumpAndSettle();
    for (final label in [
      'Film',
      'Serie',
      'Impostazioni',
      'Cambia profilo',
      'Aggiungi profilo',
      'Esci',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Amministrazione'), findsNothing);
    expect(find.text('Calendario'), findsNothing);

    await tester.tap(find.text('Film'));
    await tester.pumpAndSettle();
    expect(location(router), '/movies');
    expect(find.text('Serie'), findsNothing, reason: 'il foglio si chiude');
  });

  testWidgets('Altro: Admin per gli admin, Calendario con il calendario',
      (tester) async {
    final router = await pumpShell(tester,
        features: const SocialFeatures(friends: true, calendar: true),
        user: const JellyfinUser(
            id: 'u1', name: 'Mario', isAdministrator: true));

    await tester.tap(find.byKey(const Key('bottom-nav-/more')));
    await tester.pumpAndSettle();
    expect(find.text('Calendario'), findsOneWidget);
    await tester.tap(find.text('Amministrazione'));
    await tester.pumpAndSettle();
    expect(location(router), '/admin');
  });

  testWidgets(
      'stretto: Amici apre /friends come pagina e indietro torna alla pagina '
      'di prima', (tester) async {
    final router = await pumpShell(tester);
    await tester.tap(find.byKey(const Key('bottom-nav-/mylist')));
    await tester.pumpAndSettle();
    api.calls.clear();

    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(location(router), '/friends');
    expect(find.byType(FriendsPanel), findsOneWidget);
    expect(find.byKey(const Key('friends-panel-scrim')), findsNothing,
        reason: 'niente pannello laterale nel layout stretto');
    expect(api.calls, contains('friends'), reason: 'aprire Amici li rilegge');
    final container =
        ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
    expect(container.read(shellPanelProvider), ShellPanel.friends);

    // La freccia indietro della barra.
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(location(router), '/mylist');
    expect(find.byType(FriendsPanel), findsNothing);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  testWidgets('stretto: chiudere il pannello dal contenuto chiude la pagina',
      (tester) async {
    final router = await pumpShell(tester);

    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(location(router), '/friends');

    // Il pulsante Amici con la pagina aperta la chiude, come il pannello.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(location(router), '/home');
    expect(find.byType(FriendsPanel), findsNothing);
  });

  testWidgets(
      'largo (1440×900): barra in alto di oggi, niente barra in basso, Amici '
      'apre il pannello laterale', (tester) async {
    final router = await pumpShell(tester, size: _desktop);

    expect(find.byKey(const Key('bottom-nav-/home')), findsNothing);
    expect(find.byKey(const Key('nav-/movies')), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(location(router), '/home');
    expect(find.byKey(const Key('friends-panel-scrim')), findsOneWidget);
  });

  testWidgets('da stretto a largo con Altro aperto: niente eccezioni',
      (tester) async {
    final router = await pumpShell(tester);
    await tester.tap(find.byKey(const Key('bottom-nav-/more')));
    await tester.pumpAndSettle();

    await tester.binding.setSurfaceSize(_phoneLandscape);
    tester.view.physicalSize = _phoneLandscape * tester.view.devicePixelRatio;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(_desktop);
    tester.view.physicalSize = _desktop * tester.view.devicePixelRatio;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('nav-/movies')), findsOneWidget);

    // Il foglio rimasto aperto funziona ancora.
    await tester.tap(find.text('Serie').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(location(router), '/series');
  });

  for (final size in [_phone, _phoneLandscape]) {
    testWidgets('stretto: niente overflow a ${size.width}×${size.height}',
        (tester) async {
      final router = await pumpShell(tester,
          size: size,
          features: const SocialFeatures(
              friends: true, inbox: true, requests: true));
      expect(tester.takeException(), isNull);

      unawaited(router.push('/friends'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('bottom-nav-/more')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'stretto: con un watch party la barra in alto non va in overflow a '
        '${size.width}×${size.height}', (tester) async {
      await pumpShell(tester,
          size: size,
          groups: [testGroup()],
          features: const SocialFeatures(friends: true, inbox: true));
      expect(tester.takeException(), isNull);
      final chip = find.byKey(const Key('watch-party-button'));
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).width, greaterThanOrEqualTo(44));
      expect(find.byTooltip('Watch party · 1'), findsOneWidget);
    });

    testWidgets(
        'stretto: dentro un watch party la barra in alto non va in overflow '
        'a ${size.width}×${size.height}', (tester) async {
      await pumpShell(tester,
          size: size,
          inParty: true,
          features: const SocialFeatures(friends: true, inbox: true));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('watch-party-in-party')), findsOneWidget);
    });
  }

  testWidgets('stretto col dito: Amici non mette il fuoco nel campo',
      (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const Key('friends-search')));
    expect(field.focusNode?.hasFocus, isFalse,
        reason: 'la tastiera del telefono non si apre da sola');
  });

  testWidgets('stretto col mouse: Amici mette il fuoco nel campo come oggi',
      (tester) async {
    await pumpShell(tester, touch: false);
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const Key('friends-search')));
    expect(field.focusNode?.hasFocus, isTrue);
  });
}
