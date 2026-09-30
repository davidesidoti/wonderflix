import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/page_transitions.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
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

/// Pagina finta che pubblica un titolo dopo 380 px di scroll.
class _FakeDetail extends StatefulWidget {
  const _FakeDetail(
      {required this.title,
      required this.onPlay,
      String? id,
      this.actionLabel = 'Riproduci'})
      : id = id ?? title;

  final String title;
  final VoidCallback onPlay;
  final String actionLabel;

  /// Distingue due pagine con lo stesso titolo.
  final String id;

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
        visibleAt: (offset) => offset >= 380,
        header: ShellHeader(
            title: widget.title,
            actionLabel: widget.actionLabel,
            onAction: widget.onPlay),
        child: ListView(
          key: Key('detail-list-${widget.id}'),
          controller: _scroll,
          children: [
            for (var i = 0; i < 40; i++) SizedBox(height: 100, child: Text('r$i')),
          ],
        ),
      );
}

void main() {
  late int plays;
  late List<String> playedPages;

  Future<GoRouter> pumpRouter(WidgetTester tester,
      {List<Override> overrides = const [],
      Size size = const Size(1440, 900),
      MotionLevel motion = MotionLevel.reduced}) async {
    plays = 0;
    playedPages = [];
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
          // Titolo ed etichetta lunghi, per le finestre strette.
          GoRoute(
            path: '/long',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              _FakeDetail(
                  id: 'long',
                  title: 'Il Signore degli Anelli: la Compagnia dell\'Anello',
                  actionLabel: 'Riprendi S1:E5 · 1:12:34',
                  onPlay: () => plays++),
              underBar: false,
            ),
          ),
          // Pagine diverse con lo stesso titolo e azioni diverse.
          GoRoute(
            path: '/same/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return detailPage(
                context,
                state,
                _FakeDetail(
                    id: id, title: 'dune', onPlay: () => playedPages.add(id)),
                underBar: false,
              );
            },
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
        builder: (context, child) =>
            WfMotionScope(motion: WfMotion(motion), child: child!),
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

  testWidgets('due pagine con lo stesso titolo: "Riproduci" resta della '
      'pagina in cima', (tester) async {
    final router = await pumpRouter(tester);
    unawaited(router.push('/same/a'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('detail-list-a')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);

    unawaited(router.push('/same/b'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('detail-list-b')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);

    // Indietro: stesso titolo e stessa etichetta, ma l'azione è di A.
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-bar-play')));
    expect(playedPages, ['a']);
  });

  // Sotto una certa larghezza libera il pulsante mostra solo l'icona.
  for (final (width, compact) in [
    (1024.0, true),
    (1280.0, true),
    (1920.0, false),
  ]) {
    testWidgets('finestra larga ${width.toInt()}: titolo e pulsante lunghi '
        'stanno nella barra', (tester) async {
      final router = await pumpRouter(tester, size: Size(width, 700));
      unawaited(router.push('/long'));
      await tester.pumpAndSettle();
      await tester.drag(
          find.byKey(const Key('detail-list-long')), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('shell-bar-title')), findsOneWidget);
      final play = find.byKey(const Key('shell-bar-play'));
      expect(play, findsOneWidget);
      const label = 'Riprendi S1:E5 · 1:12:34';
      expect(find.descendant(of: play, matching: find.text(label)),
          compact ? findsNothing : findsOneWidget);
      if (compact) {
        expect(
            find.ancestor(
                of: play,
                matching: find.byWidgetPredicate(
                    (w) => w is Tooltip && w.message == label)),
            findsOneWidget);
      }
      await tester.tap(play);
      expect(plays, 1);
    });
  }

  /// Film con cast e "Simili", la scheda con più righe.
  List<Override> movieOverrides() {
    final api = FakeLibraryApi()
      ..itemsById['m1'] = testItem(id: 'm1', name: 'Dune', people: [
        {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
      ])
      ..similarItems = [testItem(id: 'm2', name: 'Arrival')];
    return [
      libraryApiProvider.overrideWithValue(api),
      // Nessuna immagine di rete nei widget test.
      imageBuilderProvider.overrideWithValue(
          (image, fit) => const ColoredBox(color: Color(0xFF333333))),
    ];
  }

  /// Apre la scheda del film. Con le animazioni complete l'onda degli
  /// scheletri è continua: si avanza a passi finché la scheda è arrivata.
  Future<ScrollController> openMovie(WidgetTester tester, GoRouter router,
      {required MotionLevel motion}) async {
    unawaited(router.push('/title/m1'));
    if (motion == MotionLevel.full) {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await tester.pumpAndSettle();
    return tester
        .widget<MovieDetailView>(find.byType(MovieDetailView))
        .controller!;
  }

  testWidgets('la scheda di un film pubblica titolo e azione principale '
      '(animazioni ridotte)', (tester) async {
    // Finestra bassa: con le animazioni ridotte il titolo compare quando la
    // riga dei pulsanti passa sotto la barra, la pagina deve arrivarci.
    final router = await pumpRouter(tester,
        size: const Size(1440, 700), overrides: movieOverrides());
    final controller =
        await openMovie(tester, router, motion: MotionLevel.reduced);
    final barTitle = find.byKey(const Key('shell-bar-title'));
    expect(barTitle, findsNothing);

    expect(controller.position.maxScrollExtent,
        greaterThan(detailBarTitleReducedOffset + 10));
    controller.jumpTo(detailBarTitleReducedOffset - 10);
    await tester.pumpAndSettle();
    expect(barTitle, findsNothing);
    controller.jumpTo(detailBarTitleReducedOffset + 10);
    await tester.pumpAndSettle();
    expect(find.descendant(of: barTitle, matching: find.text('DUNE')),
        findsOneWidget);
    expect(find.descendant(of: barTitle, matching: find.text('Riproduci')),
        findsOneWidget);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(barTitle, findsNothing);
  });

  testWidgets('animazioni complete, 1440×900: in fondo alla scheda il titolo '
      'è nella barra', (tester) async {
    final router = await pumpRouter(tester,
        overrides: movieOverrides(), motion: MotionLevel.full);
    final controller =
        await openMovie(tester, router, motion: MotionLevel.full);
    final barTitle = find.byKey(const Key('shell-bar-title'));
    expect(barTitle, findsNothing);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.descendant(of: barTitle, matching: find.text('DUNE')),
        findsOneWidget);
    expect(find.byKey(const Key('shell-bar-play')), findsOneWidget);
  });

  testWidgets('animazioni complete, 1920×1080: in fondo il testo della '
      'testata si legge ancora e il titolo non va nella barra',
      (tester) async {
    final router = await pumpRouter(tester,
        size: const Size(1920, 1080),
        overrides: movieOverrides(),
        motion: MotionLevel.full);
    final controller =
        await openMovie(tester, router, motion: MotionLevel.full);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(find.byKey(const Key('shell-bar-title')), findsNothing);

    final opacities = tester
        .widgetList<Opacity>(find.ancestor(
            of: find.descendant(
                of: find.byType(DetailHeader),
                matching: find.byType(MetaLine)),
            matching: find.byType(Opacity)))
        .map((o) => o.opacity)
        .toList();
    expect(opacities, isNotEmpty);
    expect(opacities.reduce((a, b) => a < b ? a : b),
        allOf(greaterThan(barTitleTextOpacity), lessThan(1)),
        reason: 'testo in dissolvenza ma sopra la soglia');
  });
}
