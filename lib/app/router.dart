import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/jellyfin/item_models.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/session_controller.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/detail/item_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/mylist/my_list_screen.dart';
import '../features/person/person_screen.dart';
import '../features/player/player_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/startup/splash_screen.dart';
import '../features/startup/unreachable_screen.dart';
import 'app_shell.dart';
import 'hero_launch.dart';
import 'navigation.dart';
import 'page_transitions.dart';

const _entryRoutes = {'/splash', '/login', '/unreachable'};

/// Dove deve stare l'utente in base allo stato di sessione.
/// `null` = la posizione attuale va bene.
String? sessionRedirect(SessionState session, String location) {
  String? goTo(String target) => location == target ? null : target;
  return switch (session) {
    SessionStarting() => goTo('/splash'),
    SessionSignedOut() => goTo('/login'),
    SessionUnreachable() => goTo('/unreachable'),
    SessionSignedIn() => _entryRoutes.contains(location) ? '/home' : null,
  };
}

/// Pagina del player. Con l'episodio successivo il nuovo player sostituisce
/// il precedente (`pushReplacement`, pagina nuova): con la transizione
/// predefinita, mentre compare, si vedrebbe la pagina sotto (dettaglio o
/// Home). Qui dal primo fotogramma c'è uno sfondo nero opaco e il player
/// appare in dissolvenza sopra.
Page<void> playerPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          ColoredBox(
        color: Colors.black,
        child: FadeTransition(opacity: animation, child: child),
      ),
    );

/// Dati del volo Hero passati da `openItem`/`openPerson` (`extra`).
HeroLaunch? _heroLaunch(GoRouterState state) =>
    state.extra is HeroLaunch ? state.extra as HeroLaunch : null;

/// Struttura comune delle pagine autenticate. Dopo un `push`
/// `matchedLocation` resta quello della pagina di partenza; l'URI è quello
/// della pagina in cima (senza la query, es. `?season=`).
Widget appShellBuilder(
        BuildContext context, GoRouterState state, Widget child) =>
    AppShell(location: state.uri.path, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final session = ValueNotifier<SessionState>(ref.read(sessionControllerProvider));
  ref.listen(sessionControllerProvider, (_, next) => session.value = next);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) =>
        sessionRedirect(session.value, state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: '/unreachable',
          builder: (context, state) => const UnreachableScreen()),
      GoRoute(
        path: '/play/:id',
        pageBuilder: (context, state) => playerPage(
          state,
          PlayerScreen(
            key: ValueKey(state.uri.toString()),
            args: (
              itemId: state.pathParameters['id']!,
              start: playerStartFrom(state.uri),
              party: state.uri.queryParameters['party'],
            ),
            fullscreen: state.uri.queryParameters['fs'] == '1',
          ),
        ),
      ),
      ShellRoute(
        builder: appShellBuilder,
        routes: [
          GoRoute(
              path: '/home',
              pageBuilder: (context, state) =>
                  shellPage(context, state, const HomeScreen(),
                      underBar: false)),
          GoRoute(
              path: '/movies',
              pageBuilder: (context, state) => shellPage(
                  context,
                  state,
                  const CatalogScreen(
                      key: ValueKey('movies'), kind: ItemKind.movie),
                  underBar: true)),
          GoRoute(
              path: '/series',
              pageBuilder: (context, state) => shellPage(
                  context,
                  state,
                  const CatalogScreen(
                      key: ValueKey('series'), kind: ItemKind.series),
                  underBar: true)),
          GoRoute(
              path: '/mylist',
              pageBuilder: (context, state) =>
                  shellPage(context, state, const MyListScreen(),
                      underBar: true)),
          GoRoute(
              path: '/search',
              pageBuilder: (context, state) =>
                  shellPage(context, state, const SearchScreen(),
                      underBar: true)),
          GoRoute(
              path: '/settings',
              pageBuilder: (context, state) =>
                  shellPage(context, state, const SettingsScreen(),
                      underBar: true)),
          GoRoute(
            path: '/item/:id',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              ItemDetailScreen(
                key: ValueKey(state.uri.toString()),
                itemId: state.pathParameters['id']!,
                seasonId: state.uri.queryParameters['season'],
                launch: _heroLaunch(state),
              ),
              underBar: false,
            ),
          ),
          GoRoute(
            path: '/person/:id',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              PersonScreen(
                key: ValueKey(state.pathParameters['id']),
                personId: state.pathParameters['id']!,
                launch: _heroLaunch(state),
              ),
              underBar: true,
            ),
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    session.dispose();
  });
  return router;
});
