import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/back_navigation.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/update/update_gate.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  testWidgets('Esc e Alt+← tornano indietro, la radice resta', (tester) async {
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        ShellRoute(
          builder: (context, state, child) => BackNavigationHandler(child: child),
          routes: [
            GoRoute(path: '/a', builder: (c, s) => const Text('pagina A')),
            GoRoute(path: '/b', builder: (c, s) => const Text('pagina B')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));

    router.push('/b');
    await tester.pumpAndSettle();
    expect(find.text('pagina B'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('pagina A'), findsOneWidget);

    router.push('/b');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('pagina A'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('pagina A'), findsOneWidget, reason: 'nessuna pagina da chiudere');
  });

  // Esc con un'anteprima aperta chiude solo l'anteprima: la pagina resta.
  testWidgets('Esc con un\'anteprima aperta: si chiude solo l\'anteprima',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              Scaffold(body: BackNavigationHandler(child: child)),
          routes: [
            GoRoute(path: '/a', builder: (c, s) => const Text('pagina A')),
            GoRoute(
              path: '/b',
              builder: (c, s) => Center(
                child: PosterCard(
                    item: testItem(id: 'm1', name: 'Dune'), width: 160),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider.overrideWithValue(
            (image, fit) => const ColoredBox(color: Color(0xFF333333))),
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
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

    unawaited(router.push('/b'));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(PosterCard)));
    await tester.pump(previewHoverDelay);
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/b');
    expect(find.byType(PosterCard), findsOneWidget);
    expect(find.byType(CardPreview), findsNothing);

    // Senza anteprima Esc torna indietro come sempre.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('pagina A'), findsOneWidget);
  });

  testWidgets('aggiornamento obbligatorio: Esc e Alt+← non chiudono la pagina',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        ShellRoute(
          builder: (context, state, child) => BackNavigationHandler(child: child),
          routes: [
            GoRoute(path: '/a', builder: (c, s) => const Text('pagina A')),
            GoRoute(path: '/b', builder: (c, s) => const Text('pagina B')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [updateBlockedProvider.overrideWithValue(true)],
      child: MaterialApp.router(routerConfig: router),
    ));

    router.push('/b');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('pagina B'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('pagina B'), findsOneWidget);
  });
}
