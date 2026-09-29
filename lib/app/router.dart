import 'package:flutter/foundation.dart';
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
import 'navigation.dart';

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
        builder: (context, state) => PlayerScreen(
          key: ValueKey(state.uri.toString()),
          args: (
            itemId: state.pathParameters['id']!,
            start: playerStartFrom(state.uri),
          ),
          fullscreen: state.uri.queryParameters['fs'] == '1',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          GoRoute(
              path: '/movies',
              builder: (context, state) =>
                  const CatalogScreen(key: ValueKey('movies'), kind: ItemKind.movie)),
          GoRoute(
              path: '/series',
              builder: (context, state) =>
                  const CatalogScreen(key: ValueKey('series'), kind: ItemKind.series)),
          GoRoute(path: '/mylist', builder: (context, state) => const MyListScreen()),
          GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
          GoRoute(
              path: '/settings', builder: (context, state) => const SettingsScreen()),
          GoRoute(
            path: '/item/:id',
            builder: (context, state) => ItemDetailScreen(
              key: ValueKey(state.uri.toString()),
              itemId: state.pathParameters['id']!,
              seasonId: state.uri.queryParameters['season'],
            ),
          ),
          GoRoute(
            path: '/person/:id',
            builder: (context, state) => PersonScreen(
              key: ValueKey(state.pathParameters['id']),
              personId: state.pathParameters['id']!,
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
