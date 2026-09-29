import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/back_navigation.dart';
import 'package:wonderflix/features/update/update_gate.dart';

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
