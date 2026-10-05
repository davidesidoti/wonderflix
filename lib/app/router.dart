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
import '../features/requests/requests_navigation.dart';
import '../features/requests/requests_screen.dart';
import '../features/requests/tmdb_title_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/startup/splash_screen.dart';
import '../features/startup/unreachable_screen.dart';
import 'app_shell.dart';
import 'hero_launch.dart';
import 'motion.dart';
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

/// Pagina del player (spec D §6.3). Dalla scheda o dalla Home entra in
/// dissolvenza incrociata sopra la pagina di partenza (`medium`) ed esce in
/// `fast`. Quando sostituisce un altro player (`extra` [PlayerReplacement]:
/// episodio successivo, player del gruppo) la pagina sotto non è quella di
/// partenza: dal primo fotogramma c'è uno sfondo nero opaco e il player
/// appare sopra. Chiudendolo, il nero sparisce e il player sfuma sulla
/// pagina sotto.
Page<void> playerPage(
    BuildContext context, GoRouterState state, Widget child) {
  final motion = WfMotion.of(context);
  final replacing = state.extra is PlayerReplacement;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: motion.duration(WfMotion.medium),
    reverseTransitionDuration: WfMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final faded = FadeTransition(
          opacity: animation.drive(CurveTween(curve: WfMotion.standard)),
          child: child);
      // Il nodo resta sempre (altrimenti il player si rimonterebbe); in
      // uscita il nero diventa trasparente: il player sfuma sulla pagina
      // sotto, invece di restare 150 ms su nero e poi sparire di colpo.
      return replacing
          ? ColoredBox(
              key: const Key('player-replacement-backdrop'),
              color: animation.status == AnimationStatus.reverse
                  ? Colors.transparent
                  : Colors.black,
              child: faded)
          : faded;
    },
  );
}

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
      GoRoute(
          path: '/splash',
          pageBuilder: (context, state) =>
              entryPage(context, state, const SplashScreen())),
      GoRoute(
          path: '/login',
          pageBuilder: (context, state) =>
              entryPage(context, state, const LoginScreen())),
      GoRoute(
          path: '/unreachable',
          pageBuilder: (context, state) =>
              entryPage(context, state, const UnreachableScreen())),
      GoRoute(
        path: '/play/:id',
        pageBuilder: (context, state) => playerPage(
          context,
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
              path: '/requests',
              pageBuilder: (context, state) => shellPage(
                  context,
                  state,
                  RequestsScreen(
                      key: ValueKey(state.uri.toString()),
                      initialTab:
                          RequestsTab.parse(state.uri.queryParameters['tab'])),
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
          GoRoute(
            path: '/tmdb/:type/:tmdbId',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              // Tipo o id non validi: pagina vuota (si torna indietro).
              TmdbTitleScreen.fromRoute(
                    state.pathParameters['type'],
                    state.pathParameters['tmdbId'],
                    key: ValueKey(state.uri.toString()),
                  ) ??
                  const SizedBox.shrink(),
              underBar: false,
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
