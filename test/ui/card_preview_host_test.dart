import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final overrides = [
    sessionControllerProvider
        .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    libraryApiProvider.overrideWithValue(FakeLibraryApi()),
  ];

  Future<void> pumpCards(WidgetTester tester,
      {List<VoidCallback>? taps, MotionLevel motion = MotionLevel.reduced}) async {
    await pumpApp(
      tester,
      Scaffold(
        body: ListView(
          key: const Key('page'),
          padding: const EdgeInsets.all(200),
          children: [
            Row(children: [
              PosterCard(
                  key: const Key('card-a'),
                  item: testItem(id: 'a', name: 'Alien'),
                  width: 160,
                  onTap: taps?[0]),
              const SizedBox(width: 400),
              PosterCard(
                  key: const Key('card-b'),
                  item: testItem(id: 'b', name: 'Heat'),
                  width: 160,
                  onTap: taps?[1]),
            ]),
            const SizedBox(height: 2000),
          ],
        ),
      ),
      overrides: overrides,
      motion: motion,
    );
  }

  Future<TestGesture> mouseOver(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    return mouse;
  }

  testWidgets('si apre dopo 500 ms di sosta, non prima', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(CardPreview), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('si chiude quando il mouse esce', (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  // La chiusura dell'anteprima notifica il provider: l'host stesso non deve
  // prenderla per l'apertura di un'altra e troncare la dissolvenza.
  for (final byEsc in [false, true]) {
    testWidgets(
        byEsc
            ? 'completa: Esc la chiude in dissolvenza'
            : 'completa: uscendo il mouse si chiude in dissolvenza',
        (tester) async {
      await pumpCards(tester, motion: MotionLevel.full);
      final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
      await tester.pump(previewHoverDelay);
      await tester.pumpAndSettle();
      expect(find.byType(CardPreview), findsOneWidget);

      if (byEsc) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await mouse.moveTo(const Offset(5, 5));
      }
      await tester.pump();
      await tester.pump(WfMotion.fast ~/ 2);
      expect(find.byType(CardPreview), findsOneWidget, reason: 'sta sfumando');
      final opacity = tester
          .widget<Opacity>(find
              .ancestor(
                  of: find.byType(CardPreview), matching: find.byType(Opacity))
              .first)
          .opacity;
      expect(opacity, greaterThan(0));
      expect(opacity, lessThan(1));
      await tester.pump(WfMotion.fast);
      await tester.pump();
      expect(find.byType(CardPreview), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('uscire prima dei 500 ms: niente anteprima, nessun timer',
      (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('Esc la chiude', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('dopo Esc si riapre solo quando il mouse torna sulla card',
      (tester) async {
    await pumpCards(tester);
    final card = find.byKey(const Key('card-a'));
    final mouse = await mouseOver(tester, card);
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // La card torna scoperta sotto il mouse fermo: non la riapre.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CardPreview), findsNothing);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(seconds: 1));
    await mouse.moveTo(tester.getCenter(card));
    await tester.pump(previewHoverDelay);
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('la rotella la chiude', (tester) async {
    await pumpCards(tester);
    await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    final wheel = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(CardPreview))));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
  });

  testWidgets('da un\'anteprima a un\'altra card: si apre subito, una sola',
      (tester) async {
    await pumpCards(tester);
    final mouse = await mouseOver(tester, find.byKey(const Key('card-a')));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('card-b'))));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CardPreview), findsOneWidget);
    expect(find.text('HEAT'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('tocco: apre la scheda, niente anteprima', (tester) async {
    var taps = 0;
    await pumpCards(tester, taps: [() => taps++, () {}]);
    await tester.tap(find.byKey(const Key('card-a')));
    await tester.pump(const Duration(seconds: 1));
    expect(taps, 1);
    expect(find.byType(CardPreview), findsNothing);
  });

  // --- Con un vero router: player, scheda, riga orizzontale. ---

  final appOverrides = [
    appConfigProvider.overrideWithValue(testAppConfig),
    serverEventsBindingProvider.overrideWithValue(null),
    imageBuilderProvider.overrideWithValue(
        (image, fit) => const ColoredBox(color: Color(0xFF333333))),
    ...overrides,
  ];

  /// Pagina con una riga orizzontale di due card (con sorgente del volo) e
  /// le rotte finte della scheda e del player; animazioni ridotte.
  Future<ScrollController> pumpRouted(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final row = ScrollController();
    addTearDown(row.dispose);
    // Come in app: pagine e scheda nella shell, il player fuori (aprendolo
    // la pagina della card resta in cima al navigatore della shell).
    final router = GoRouter(routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(body: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Padding(
              padding: const EdgeInsets.all(200),
              child: SizedBox(
                height: 400,
                child: ListView(
                  controller: row,
                  scrollDirection: Axis.horizontal,
                  children: [
                    PosterCard(
                        key: const Key('card-a'),
                        item: testItem(id: 'a', name: 'Alien'),
                        heroSource: 'riga',
                        width: 160),
                    const SizedBox(width: 400),
                    PosterCard(
                        key: const Key('card-b'),
                        item: testItem(id: 'b', name: 'Heat'),
                        heroSource: 'riga',
                        width: 160),
                    const SizedBox(width: 2000),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/item/:id',
            builder: (context, state) => Text(
                'scheda ${state.pathParameters['id']} '
                '${state.extra == null ? 'senza volo' : 'con volo'}'),
          ),
        ],
      ),
      GoRoute(
        path: '/play/:id',
        builder: (context, state) =>
            Scaffold(body: Text('player ${state.pathParameters['id']}')),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: appOverrides,
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => WfMotionScope(
            motion: const WfMotion(MotionLevel.reduced), child: child!),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    return row;
  }

  Future<void> openPreviewOn(WidgetTester tester, Finder card) async {
    await mouseOver(tester, card);
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsOneWidget);
  }

  testWidgets('"Riproduci": chiude l\'anteprima e apre il player, non la scheda',
      (tester) async {
    await pumpRouted(tester);
    await openPreviewOn(tester, find.byKey(const Key('card-a')));

    final container =
        ProviderScope.containerOf(tester.element(find.byType(CardPreview)));
    await tester.tap(find.byTooltip('Riproduci'));
    // Chiusa dal pulsante, prima del fotogramma: la pagina della card resta
    // in cima al navigatore della shell e il player non la copre ancora.
    expect(container.read(cardPreviewProvider).openId, isNull);
    await tester.pump();
    expect(find.byType(CardPreview), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('player a'), findsOneWidget);
    expect(find.textContaining('scheda'), findsNothing);
    expect(find.byType(CardPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Dettagli" con animazioni ridotte: scheda senza volo',
      (tester) async {
    await pumpRouted(tester);
    await openPreviewOn(tester, find.byKey(const Key('card-a')));

    await tester.tap(find.byTooltip('Dettagli'));
    await tester.pump();
    expect(find.byType(CardPreview), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(wfHeroFlightKey), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('scheda a senza volo'), findsOneWidget);
    expect(find.byType(CardPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la finestra non più attiva la chiude', (tester) async {
    await pumpRouted(tester);
    await openPreviewOn(tester, find.byKey(const Key('card-a')));
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo scorrimento della riga la chiude', (tester) async {
    final row = await pumpRouted(tester);
    await openPreviewOn(tester, find.byKey(const Key('card-a')));

    row.jumpTo(100);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card tolta dall\'albero ad anteprima aperta: provider chiuso',
      (tester) async {
    final container = ProviderContainer.test(overrides: appOverrides);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: PosterCard(
                key: const Key('card-a'),
                item: testItem(id: 'a', name: 'Alien'),
                width: 160),
          ),
        ),
      ),
    ));
    await openPreviewOn(tester, find.byKey(const Key('card-a')));
    expect(container.read(cardPreviewProvider).openId, isNotNull);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const Directionality(
          textDirection: TextDirection.ltr, child: Text('vuota')),
    ));
    await tester.pump();
    expect(container.read(cardPreviewProvider).openId, isNull);
    expect(tester.takeException(), isNull);
  });
}
