import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/tv_shell.dart';
import 'package:wonderflix/app/tv_sidebar.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/inbox/inbox_button.dart';
import 'package:wonderflix/features/friends/friends_button.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_button.dart';
import 'package:wonderflix/ui/tv_focusable.dart';
import 'package:wonderflix/app/shell_bottom_bar.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

/// 1080p a densità 2: lo schermo che vede l'app sulla TV.
const _tvSize = Size(960, 540);

const _navRoutes = [
  '/search',
  '/home',
  '/movies',
  '/series',
  'tonight',
  '/mylist',
  '/requests',
];

void main() {
  var tonightCalls = 0;
  var exitCalls = 0;
  late FakeSessionController session;

  GoRouter router() {
    GoRoute page(String path, {Widget? child}) => GoRoute(
      path: path,
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: child ?? Center(child: Text('pagina $path')),
      ),
    );
    return GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => TvShell(
            onTonight: () => tonightCalls++,
            onExit: () => exitCalls++,
            child: child,
          ),
          routes: [
            page('/home'),
            page(
              '/movies',
              child: Center(
                child: TvFocusable(
                  autofocus: true,
                  onActivate: () {},
                  child: const SizedBox(
                    key: Key('movies-content'),
                    width: 100,
                    height: 40,
                  ),
                ),
              ),
            ),
            page('/series'),
            page('/mylist'),
            page('/requests'),
            page('/search'),
            page('/settings'),
            page('/item/:id'),
          ],
        ),
      ],
    );
  }

  Future<GoRouter> pumpShell(
    WidgetTester tester, {
    bool requests = true,
  }) async {
    tonightCalls = 0;
    exitCalls = 0;
    session = FakeSessionController(const SessionSignedIn(testUser));
    final r = router();
    await pumpAppRouter(
      tester,
      r,
      tv: true,
      surfaceSize: _tvSize,
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        requestsAvailableProvider.overrideWithValue(requests),
      ],
    );
    await tester.pumpAndSettle();
    return r;
  }

  String location(GoRouter r) =>
      r.routerDelegate.currentConfiguration.last.matchedLocation;

  Finder nav(String route) => find.byKey(Key('tv-nav-$route'));

  Future<void> focusNav(WidgetTester tester, String route) async {
    Focus.of(tester.element(nav(route))).requestFocus();
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
  }

  const warning = 'Premi di nuovo Indietro per uscire';

  testWidgets('la barra ha le voci in ordine, con Richieste solo se c\'è', (
    tester,
  ) async {
    await pumpShell(tester);

    double top(String route) => tester.getTopLeft(nav(route)).dy;
    final ys = [for (final route in _navRoutes) top(route)];
    expect(ys, [...ys]..sort());
    expect(ys.toSet().length, ys.length);
    // L'avatar sta in fondo, sotto tutte le voci.
    expect(
      tester.getTopLeft(find.byKey(const Key('tv-account'))).dy,
      greaterThan(ys.last),
    );
  });

  testWidgets('senza le richieste manca la voce Richieste', (tester) async {
    await pumpShell(tester, requests: false);

    expect(nav('/requests'), findsNothing);
    expect(nav('/mylist'), findsOneWidget);
  });

  testWidgets('chiusa solo icone, col focus larga coi nomi', (tester) async {
    await pumpShell(tester);

    expect(
      tester.getSize(find.byType(TvSidebar)).width,
      tvSidebarCollapsedWidth,
    );
    for (final label in [
      'Cerca',
      'Home',
      'Film',
      'Serie',
      'Stasera',
      'La mia lista',
      'Richieste',
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }

    await focusNav(tester, '/movies');

    expect(
      tester.getSize(find.byType(TvSidebar)).width,
      tvSidebarExpandedWidth,
    );
    for (final label in ['Cerca', 'Home', 'Film', 'Serie', 'Stasera']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('OK su Film porta a /movies e il focus va al contenuto', (
    tester,
  ) async {
    final r = await pumpShell(tester);

    await focusNav(tester, '/movies');
    await select(tester);

    expect(location(r), '/movies');
    final content = Focus.of(
      tester.element(find.byKey(const Key('movies-content'))),
    );
    expect(content.hasPrimaryFocus, isTrue);
    expect(
      tester.getSize(find.byType(TvSidebar)).width,
      tvSidebarCollapsedWidth,
    );
  });

  testWidgets(
    'senza un elemento con autofocus il focus va al primo del contenuto',
    (tester) async {
      final r = await pumpShell(tester);

      await focusNav(tester, '/series');
      await select(tester);

      expect(location(r), '/series');
      // Nessuno nella pagina può prenderlo: resta fuori dalla barra.
      final focused = FocusManager.instance.primaryFocus!;
      expect(
        find.descendant(
          of: find.byType(TvSidebar),
          matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode == focused,
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('OK su Stasera apre la finestra di Stasera', (tester) async {
    await pumpShell(tester);

    await focusNav(tester, 'tonight');
    await select(tester);

    expect(tonightCalls, 1);
  });

  testWidgets('l\'avatar apre il menu dell\'account', (tester) async {
    final r = await pumpShell(tester);

    Focus.of(
      tester.element(find.byKey(const Key('tv-account'))),
    ).requestFocus();
    await tester.pumpAndSettle();
    await select(tester);

    final labels = [
      'Cambia account',
      'Aggiungi account',
      'Impostazioni',
      'Esci',
    ];
    final ys = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
    expect(ys, [...ys]..sort());

    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    expect(location(r), '/settings');
  });

  testWidgets('Esci dal menu dell\'account chiude la sessione', (tester) async {
    await pumpShell(tester);

    Focus.of(
      tester.element(find.byKey(const Key('tv-account'))),
    ).requestFocus();
    await tester.pumpAndSettle();
    await select(tester);
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();

    expect(session.logoutCalls, 1);
  });

  testWidgets('niente pulsanti del PC, barra in basso o barra in alto', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byType(WatchPartyButton), findsNothing);
    expect(find.byType(FriendsButton), findsNothing);
    expect(find.byType(InboxButton), findsNothing);
    expect(find.byType(ShellBottomBar), findsNothing);
    expect(find.byKey(const Key('user-menu')), findsNothing);
  });

  testWidgets('Indietro da una voce porta a /home', (tester) async {
    final r = await pumpShell(tester);
    r.go('/movies');
    await tester.pumpAndSettle();

    await back(tester);
    await tester.pumpAndSettle();

    expect(location(r), '/home');
    expect(exitCalls, 0);
    expect(find.text(warning), findsNothing);
  });

  testWidgets(
    'da /home serve un secondo Indietro entro la finestra per uscire',
    (tester) async {
      final r = await pumpShell(tester);

      await back(tester);
      expect(find.text(warning), findsOneWidget);
      expect(exitCalls, 0);
      expect(location(r), '/home');

      await tester.pump(const Duration(seconds: 1));
      await back(tester);
      expect(exitCalls, 1);
    },
  );

  testWidgets('passata la finestra l\'avviso torna a comparire', (
    tester,
  ) async {
    await pumpShell(tester);

    await back(tester);
    // L'avviso sparisce da solo (il timer parte a fine animazione).
    await tester.pump(tvExitWindow + const Duration(seconds: 1));
    await tester.pump(tvExitWindow + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(warning), findsNothing);

    await back(tester);
    expect(find.text(warning), findsOneWidget);
    expect(exitCalls, 0);
  });

  testWidgets('su una pagina profonda Indietro torna indietro', (tester) async {
    final r = await pumpShell(tester);
    unawaited(r.push('/item/x'));
    await tester.pumpAndSettle();
    expect(location(r), '/item/x');

    await back(tester);
    await tester.pumpAndSettle();

    expect(location(r), '/home');
    expect(find.text(warning), findsNothing);
    expect(exitCalls, 0);
  });
}
