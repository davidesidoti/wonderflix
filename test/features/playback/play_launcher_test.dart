import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/features/playback/play_launcher.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;

  setUp(() => library = FakeLibraryApi());

  /// Pulsante "play" che chiama [playItem]; la route del player mostra id e
  /// posizione di partenza ricevuti.
  Future<GoRouter> pumpLauncher(WidgetTester tester, JellyfinItem item,
      {bool fromStart = false, bool trailer = false}) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => trailer
                  ? playTrailer(context, ref, item)
                  : playItem(context, ref, item, fromStart: fromStart),
              child: const Text('play'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/play/:id',
        builder: (context, state) => Text(
            'player ${state.pathParameters['id']} ${state.uri.queryParameters['start'] ?? '-'}'),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
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
    return router;
  }

  Future<void> tapPlay(WidgetTester tester) async {
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
  }

  const minutes23 = 23 * 60 * 10000000;

  testWidgets('film iniziato: riprende dal minutaggio', (tester) async {
    await pumpLauncher(tester, testItem(id: 'm1', positionTicks: minutes23));
    await tapPlay(tester);
    expect(find.text('player m1 1380000'), findsOneWidget);
  });

  testWidgets('Ricomincia: dall\'inizio', (tester) async {
    await pumpLauncher(tester, testItem(id: 'm1', positionTicks: minutes23),
        fromStart: true);
    await tapPlay(tester);
    expect(find.text('player m1 -'), findsOneWidget);
  });

  testWidgets('film già visto: dall\'inizio', (tester) async {
    await pumpLauncher(
        tester, testItem(id: 'm1', played: true, positionTicks: minutes23));
    await tapPlay(tester);
    expect(find.text('player m1 -'), findsOneWidget);
  });

  testWidgets('i dati utente aggiornati hanno la precedenza', (tester) async {
    await pumpLauncher(tester, testItem(id: 'm1'));
    ProviderScope.containerOf(tester.element(find.text('play')))
        .read(userDataOverridesProvider.notifier)
        .apply('m1', const UserItemData(playbackPositionTicks: minutes23));
    await tapPlay(tester);
    expect(find.text('player m1 1380000'), findsOneWidget);
  });

  testWidgets('serie: riproduce il prossimo episodio', (tester) async {
    library.nextUpItems = [
      testItem(id: 'e5', kind: ItemKind.episode, seriesId: 's1'),
    ];
    await pumpLauncher(tester, testItem(id: 's1', kind: ItemKind.series));
    await tapPlay(tester);
    expect(find.text('player e5 -'), findsOneWidget);
    expect(library.nextUpCalls, ['s1']);
  });

  testWidgets('doppio clic: un solo player', (tester) async {
    library.nextUpItems = [
      testItem(id: 'e5', kind: ItemKind.episode, seriesId: 's1'),
    ];
    final router =
        await pumpLauncher(tester, testItem(id: 's1', kind: ItemKind.series));
    await tester.tap(find.text('play'));
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
    expect(library.nextUpCalls, ['s1']);
    expect(find.text('player e5 -'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('play'), findsOneWidget, reason: 'nessun secondo player');

    // Uscito dal player si può riprodurre di nuovo.
    await tapPlay(tester);
    expect(find.text('player e5 -'), findsOneWidget);
  });

  testWidgets('player tolto senza uscirne (redirect): si riproduce di nuovo',
      (tester) async {
    final router = await pumpLauncher(tester, testItem(id: 'm1'));
    await tapPlay(tester);
    expect(find.text('player m1 -'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    await tapPlay(tester);
    expect(find.text('player m1 -'), findsOneWidget);
  });

  testWidgets('serie senza episodi: avviso', (tester) async {
    await pumpLauncher(tester, testItem(id: 's1', kind: ItemKind.series));
    await tapPlay(tester);
    expect(find.text('Nessun episodio disponibile.'), findsOneWidget);
    expect(find.text('play'), findsOneWidget);
  });

  testWidgets('trailer locale: si apre nel player dall\'inizio',
      (tester) async {
    library.localTrailerItems['m1'] = [
      testItem(id: 't1', kind: ItemKind.other),
    ];
    await pumpLauncher(
        tester, testItem(id: 'm1', localTrailers: 1, positionTicks: minutes23),
        trailer: true);
    await tapPlay(tester);
    expect(find.text('player t1 -'), findsOneWidget);
  });
}
