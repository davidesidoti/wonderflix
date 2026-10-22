import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/page_transitions.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

/// Shell con un vero `GoRouter` e le pagine della shell, come in `router.dart`,
/// ma con pagine finte scorrevoli.
void main() {
  Widget page(String name) => ListView(
        key: Key('page-$name'),
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(height: 100, child: Text('$name $i')),
        ],
      );

  Future<GoRouter> pumpRouter(WidgetTester tester, String initial) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        ShellRoute(
          builder: appShellBuilder,
          routes: [
            GoRoute(
                path: '/home',
                pageBuilder: (context, state) =>
                    shellPage(context, state, page('home'),
                        underBar: false)),
            GoRoute(
                path: '/movies',
                pageBuilder: (context, state) =>
                    shellPage(context, state, page('movies'),
                        underBar: true)),
            GoRoute(
                path: '/item/:id',
                pageBuilder: (context, state) => detailPage(context, state,
                    page('item-${state.pathParameters['id']}'),
                    underBar: false)),
            GoRoute(
                path: '/person/:id',
                pageBuilder: (context, state) => detailPage(context, state,
                    page('person-${state.pathParameters['id']}'),
                    underBar: true)),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        // Nessun elenco dei watch party (né timer).
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  double topOf(WidgetTester tester, String name) =>
      tester.getTopLeft(find.byKey(Key('page-$name'))).dy;

  bool underlineVisible(WidgetTester tester) {
    final indicator = find.byKey(const Key('nav-indicator'));
    if (indicator.evaluate().isEmpty) return false;
    final fade = tester.widget<AnimatedOpacity>(find.descendant(
        of: indicator, matching: find.byType(AnimatedOpacity)));
    return fade.opacity > 0;
  }

  void expectUnderlineUnder(WidgetTester tester, String route) {
    expect(underlineVisible(tester), isTrue);
    final indicator = tester.getRect(find.byKey(const Key('nav-indicator')));
    final item = tester.getRect(find.byKey(Key('nav-$route')));
    expect(indicator.left, closeTo(item.left, 0.5));
    expect(indicator.width, closeTo(item.width, 0.5));
  }

  testWidgets('la shell riceve la pagina spinta, senza query', (tester) async {
    final router = await pumpRouter(tester, '/movies');
    unawaited(router.push('/item/m1?season=s1'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppShell>(find.byType(AppShell)).location, '/item/m1');
  });

  testWidgets('scheda aperta da Film: a tutta altezza, nessuna sottolineatura',
      (tester) async {
    final router = await pumpRouter(tester, '/movies');
    expect(topOf(tester, 'movies'), shellBarHeight);
    expectUnderlineUnder(tester, '/movies');

    unawaited(router.push('/item/m1'));
    await tester.pumpAndSettle();
    expect(topOf(tester, 'item-m1'), 0);
    expect(underlineVisible(tester), isFalse);
  });

  testWidgets('persona aperta dalla Home: sotto la barra, nessuna '
      'sottolineatura', (tester) async {
    final router = await pumpRouter(tester, '/home');
    expect(topOf(tester, 'home'), 0);

    unawaited(router.push('/person/p1'));
    await tester.pumpAndSettle();
    expect(topOf(tester, 'person-p1'), shellBarHeight);
    expect(underlineVisible(tester), isFalse);
  });

  testWidgets('go dopo un push: sottolineatura sotto la voce giusta',
      (tester) async {
    final router = await pumpRouter(tester, '/home');
    expectUnderlineUnder(tester, '/home');

    unawaited(router.push('/item/m1'));
    await tester.pumpAndSettle();
    router.go('/movies');
    await tester.pumpAndSettle();
    expectUnderlineUnder(tester, '/movies');
    expect(topOf(tester, 'movies'), shellBarHeight);
  });

  double backdrop(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('shell-bar-backdrop')))
      .opacity;

  testWidgets('barra scura per pagina: tornando indietro si ritrova',
      (tester) async {
    final router = await pumpRouter(tester, '/home');
    expect(backdrop(tester), 0);
    await tester.drag(find.byKey(const Key('page-home')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(backdrop(tester), 1);

    // La scheda nuova parte dall'alto.
    unawaited(router.push('/item/m1'));
    await tester.pumpAndSettle();
    expect(backdrop(tester), 0);

    // La Home è ancora scorsa.
    router.pop();
    await tester.pumpAndSettle();
    expect(backdrop(tester), 1);
  });

  testWidgets('barra chiara tornando su una pagina non scorsa',
      (tester) async {
    final router = await pumpRouter(tester, '/movies');
    unawaited(router.push('/item/m1'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('page-item-m1')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(backdrop(tester), 1);

    router.pop();
    await tester.pumpAndSettle();
    expect(backdrop(tester), 0);

    await tester.drag(
        find.byKey(const Key('page-movies')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(backdrop(tester), 1);
    router.go('/home');
    await tester.pumpAndSettle();
    expect(backdrop(tester), 0);
  });
}
