import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/page_transitions.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/header_parallax.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/detail/movie_detail_view.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

/// Pagina finta che pubblica un titolo dopo 380 px, come la scheda.
class _FakeDetail extends StatefulWidget {
  const _FakeDetail({required this.title, required this.onPlay});

  final String title;
  final VoidCallback onPlay;

  @override
  State<_FakeDetail> createState() => _FakeDetailState();
}

class _FakeDetailState extends State<_FakeDetail> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellHeaderPublisher(
        controller: _scroll,
        threshold: 380,
        header: ShellHeader(
            title: widget.title, actionLabel: 'Riproduci', onAction: widget.onPlay),
        child: ListView(
          key: Key('detail-list-${widget.title}'),
          controller: _scroll,
          children: [
            for (var i = 0; i < 40; i++) SizedBox(height: 100, child: Text('r$i')),
          ],
        ),
      );
}

void main() {
  late int plays;

  Future<GoRouter> pumpRouter(WidgetTester tester,
      {List<Override> overrides = const [],
      Size size = const Size(1440, 900)}) async {
    plays = 0;
    final router = GoRouter(initialLocation: '/home', routes: [
      ShellRoute(
        builder: appShellBuilder,
        routes: [
          // Scheda vera, per il titolo pubblicato dalla vista del film.
          GoRoute(
            path: '/title/:id',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              ItemDetailScreen(itemId: state.pathParameters['id']!),
              underBar: false,
            ),
          ),
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => shellPage(
                context, state, const Text('home'), underBar: false),
          ),
          GoRoute(
            path: '/item/:id',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              _FakeDetail(
                  title: state.pathParameters['id']!, onPlay: () => plays++),
              underBar: false,
            ),
          ),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
        ...overrides,
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

  testWidgets('il titolo compare nella barra oltre la soglia, e va via',
      (tester) async {
    final router = await pumpRouter(tester);
    unawaited(router.push('/item/dune'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-bar-title')), findsNothing);

    final list = find.byKey(const Key('detail-list-dune'));
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shell-bar-play')));
    expect(plays, 1);

    await tester.drag(list, const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsNothing);

    // Di nuovo oltre la soglia e poi indietro: la Home non ha titolo.
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsNothing);
  });

  testWidgets('tornando indietro la barra ritrova il titolo della pagina '
      'in cima', (tester) async {
    final router = await pumpRouter(tester);
    unawaited(router.push('/item/dune'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('detail-list-dune')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);

    // Una scheda nuova sopra parte senza titolo.
    unawaited(router.push('/item/arrival'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-bar-title')), findsNothing);

    // Indietro: la prima scheda è ancora scorsa, il suo titolo torna.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);

    // Chiusa anche lei: la Home non ha titolo.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-bar-title')), findsNothing);
  });

  testWidgets('la scheda di un film pubblica titolo e azione principale',
      (tester) async {
    // Cast, simili e finestra bassa: la pagina deve poter scorrere oltre la
    // soglia.
    final api = FakeLibraryApi()
      ..itemsById['m1'] = testItem(id: 'm1', name: 'Dune', people: [
        {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
      ])
      ..similarItems = [testItem(id: 'm2', name: 'Arrival')];
    final router =
        await pumpRouter(tester, size: const Size(1440, 700), overrides: [
      libraryApiProvider.overrideWithValue(api),
      // Nessuna immagine di rete nei widget test.
      imageBuilderProvider.overrideWithValue(
          (image, fit) => const ColoredBox(color: Color(0xFF333333))),
    ]);
    unawaited(router.push('/title/m1'));
    await tester.pumpAndSettle();
    final barTitle = find.byKey(const Key('shell-bar-title'));
    expect(barTitle, findsNothing);

    final controller =
        tester.widget<MovieDetailView>(find.byType(MovieDetailView)).controller!;
    expect(controller.position.maxScrollExtent,
        greaterThan(detailBarTitleOffset + 10));
    controller.jumpTo(detailBarTitleOffset + 10);
    await tester.pumpAndSettle();
    expect(find.descendant(of: barTitle, matching: find.text('DUNE')),
        findsOneWidget);
    expect(find.descendant(of: barTitle, matching: find.text('Riproduci')),
        findsOneWidget);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(barTitle, findsNothing);
  });
}
