import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/app_shell.dart';
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
  final searchText = TextEditingController(text: 'abc');

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
            // Senza `autofocus`: il focus lo deve portare la shell.
            page(
              '/series',
              child: Center(
                child: TvFocusable(
                  onActivate: () {},
                  child: const SizedBox(
                    key: Key('series-content'),
                    width: 100,
                    height: 40,
                  ),
                ),
              ),
            ),
            page('/mylist'),
            page('/requests'),
            page(
              '/search',
              child: Center(
                child: SizedBox(
                  width: 200,
                  child: TextField(
                    key: const Key('search-field'),
                    controller: searchText,
                  ),
                ),
              ),
            ),
            page(
              '/settings',
              child: Center(
                child: TvFocusable(
                  onActivate: () {},
                  child: const SizedBox(
                    key: Key('settings-content'),
                    width: 100,
                    height: 40,
                  ),
                ),
              ),
            ),
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

  testWidgets('le pagine non lasciano il posto alle barre del PC e del '
      'telefono', (tester) async {
    await pumpApp(
      tester,
      const ShellPageFrame(
        underBar: true,
        child: SizedBox.expand(key: Key('page')),
      ),
      tv: true,
      surfaceSize: _tvSize,
    );

    expect(
      tester.getRect(find.byKey(const Key('page'))),
      Offset.zero & _tvSize,
    );
  });

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

  testWidgets('Su e Giù si muovono solo tra le voci della barra, aperta', (
    tester,
  ) async {
    await pumpShell(tester);
    await focusNav(tester, '/series');

    bool focused(Finder f) => Focus.of(tester.element(f)).hasPrimaryFocus;
    double width() => tester.getSize(find.byType(TvSidebar)).width;
    final account = find.byKey(const Key('tv-account'));
    final down = [nav('tonight'), nav('/mylist'), nav('/requests'), account];
    for (final f in down) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focused(f), isTrue, reason: '$f');
      expect(width(), tvSidebarExpandedWidth);
    }
    // In fondo resta sull'avatar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(account), isTrue);
    expect(width(), tvSidebarExpandedWidth);

    for (final f in [
      nav('/requests'),
      nav('/mylist'),
      nav('tonight'),
      nav('/series'),
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focused(f), isTrue, reason: '$f');
      expect(width(), tvSidebarExpandedWidth);
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
      // Nessuno nella pagina può prenderlo: la shell lo dà alla prima voce
      // vera, non a un nodo invisibile.
      final content = Focus.of(
        tester.element(find.byKey(const Key('series-content'))),
      );
      expect(content.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets('OK su Stasera apre la finestra di Stasera', (tester) async {
    await pumpShell(tester);

    await focusNav(tester, 'tonight');
    await select(tester);

    expect(tonightCalls, 1);
  });

  testWidgets('Sinistra in un campo di testo muove il cursore, non il focus', (
    tester,
  ) async {
    final r = await pumpShell(tester);
    r.go('/search');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-field')));
    await tester.pump();
    searchText.selection = const TextSelection.collapsed(offset: 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(searchText.selection.baseOffset, 2);
    final field = FocusManager.instance.primaryFocus!;
    expect(
      field.context!.findAncestorWidgetOfExactType<EditableText>(),
      isNotNull,
    );
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

  testWidgets('Impostazioni dal menu porta il focus nel contenuto', (
    tester,
  ) async {
    final r = await pumpShell(tester);

    Focus.of(
      tester.element(find.byKey(const Key('tv-account'))),
    ).requestFocus();
    await tester.pumpAndSettle();
    await select(tester);
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();

    expect(location(r), '/settings');
    final content = Focus.of(
      tester.element(find.byKey(const Key('settings-content'))),
    );
    expect(content.hasPrimaryFocus, isTrue);
    expect(
      tester.getSize(find.byType(TvSidebar)).width,
      tvSidebarCollapsedWidth,
    );
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

  testWidgets('Sinistra dal primo elemento del contenuto va alla voce della '
      'sezione', (tester) async {
    await pumpShell(tester);
    await focusNav(tester, '/movies');
    await select(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(nav('/movies'))).hasPrimaryFocus, isTrue);
  });

  testWidgets('Destra dalla barra torna all\'elemento che aveva il focus', (
    tester,
  ) async {
    await pumpShell(tester);
    await focusNav(tester, '/movies');
    await select(tester);
    final card = Focus.of(
      tester.element(find.byKey(const Key('movies-content'))),
    );
    expect(card.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(card.hasPrimaryFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(card.hasPrimaryFocus, isTrue);
  });

  testWidgets('lasciata la radice e tornata, l\'avviso torna a comparire', (
    tester,
  ) async {
    final r = await pumpShell(tester);

    await back(tester);
    expect(find.text(warning), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    r.go('/movies');
    await tester.pumpAndSettle();
    r.go('/home');
    await tester.pumpAndSettle();

    await back(tester);
    expect(exitCalls, 0);
    expect(find.text(warning), findsOneWidget);
  });
}
