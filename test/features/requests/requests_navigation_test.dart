import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_navigation.dart';

import '../../support/requests_fakes.dart';

void main() {
  test('rotta della scheda da richiedere', () {
    expect(tmdbRoute(RequestMediaType.movie, 693134), '/tmdb/movie/693134');
    expect(tmdbRoute(RequestMediaType.tv, 90228), '/tmdb/tv/90228');
  });

  testWidgets(
      'apre la scheda da richiedere, o quella della libreria se il titolo è già lì',
      (tester) async {
    final titles = {
      'film': testRequestable(tmdbId: 693134),
      'serie in parte': testRequestable(
          tmdbId: 90228,
          type: RequestMediaType.tv,
          status: TitleStatus.partial,
          jellyfinItemId: 'abc'),
      'già qui': testRequestable(
          tmdbId: 438631, status: TitleStatus.available, jellyfinItemId: 'ee39'),
    };
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Column(children: [
            for (final entry in titles.entries)
              TextButton(
                onPressed: () => openRequestable(context, entry.value),
                child: Text(entry.key),
              ),
          ]),
        ),
      ),
      GoRoute(
          path: '/tmdb/:type/:tmdbId',
          builder: (context, state) => const Text('scheda tmdb')),
      GoRoute(
          path: '/item/:id', builder: (context, state) => const Text('scheda')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // `currentConfiguration.uri` resta alla rotta di base dopo un `push`:
    // la rotta in cima la dà `router.state`.
    String path() => router.state.uri.path;

    await tester.tap(find.text('film'));
    await tester.pumpAndSettle();
    expect(path(), '/tmdb/movie/693134');
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('serie in parte'));
    await tester.pumpAndSettle();
    expect(path(), '/tmdb/tv/90228');
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('già qui'));
    await tester.pumpAndSettle();
    expect(path(), '/item/ee39');
  });

  testWidgets('pagina Richieste e richieste: libreria o scheda da richiedere',
      (tester) async {
    late BuildContext home;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          home = context;
          return const Scaffold(body: Text('home'));
        },
      ),
      GoRoute(path: '/requests', builder: (context, state) => const Text('richieste')),
      GoRoute(path: '/item/:id', builder: (context, state) => const Text('scheda')),
      GoRoute(
          path: '/tmdb/:type/:tmdbId',
          builder: (context, state) => const Text('scheda tmdb')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    openRequests(home, tab: RequestsTab.pending);
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/requests?tab=pending');

    router.go('/');
    await tester.pumpAndSettle();
    openRequest(home, testMediaRequest(id: 4, jellyfinItemId: 'abc'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/abc');

    router.go('/');
    await tester.pumpAndSettle();
    openRequest(home, testMediaRequest(id: 4));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/tmdb/movie/693004');
  });

  test('scheda della pagina dall\'indirizzo', () {
    expect(RequestsTab.parse('pending'), RequestsTab.pending);
    expect(RequestsTab.parse('mine'), RequestsTab.mine);
    expect(RequestsTab.parse('all'), RequestsTab.all);
    expect(RequestsTab.parse('boh'), isNull);
    expect(RequestsTab.parse(null), isNull);
    expect(RequestsTab.pending.filter, RequestsFilter.pending);
  });
}
