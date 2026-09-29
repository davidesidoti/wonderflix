import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../support/test_data.dart';

void main() {
  const signedIn = SessionSignedIn(testUser);

  test('avvio: tutto porta allo splash', () {
    expect(sessionRedirect(const SessionStarting(), '/home'), '/splash');
    expect(sessionRedirect(const SessionStarting(), '/splash'), isNull);
  });

  test('non autenticato: tutto porta al login', () {
    expect(sessionRedirect(const SessionSignedOut(), '/home'), '/login');
    expect(sessionRedirect(const SessionSignedOut(), '/login'), isNull);
  });

  test('server irraggiungibile: schermata dedicata', () {
    expect(sessionRedirect(const SessionUnreachable(), '/splash'),
        '/unreachable');
    expect(sessionRedirect(const SessionUnreachable(), '/unreachable'), isNull);
  });

  test('autenticato: dalle schermate di ingresso alla Home, altrimenti resta',
      () {
    expect(sessionRedirect(signedIn, '/splash'), '/home');
    expect(sessionRedirect(signedIn, '/login'), '/home');
    expect(sessionRedirect(signedIn, '/unreachable'), '/home');
    expect(sessionRedirect(signedIn, '/home'), isNull);
  });

  test('il player resta aperto da autenticati, porta al login da disconnessi',
      () {
    expect(sessionRedirect(signedIn, '/play/m1'), isNull);
    expect(sessionRedirect(const SessionSignedOut(expired: true), '/play/m1'),
        '/login');
  });

  testWidgets('player: sotto la transizione solo nero, mai la pagina sotto',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/play/:id',
        pageBuilder: (context, state) =>
            playerPage(state, Text('player ${state.pathParameters['id']}')),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    ColoredBox backdrop(String text) => tester.widget<ColoredBox>(find
        .ancestor(of: find.text(text), matching: find.byType(ColoredBox))
        .last);

    router.push('/play/e4');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(backdrop('player e4').color, Colors.black);
    expect(
        tester.getSize(find
            .ancestor(of: find.text('player e4'), matching: find.byType(ColoredBox))
            .last),
        tester.view.physicalSize / tester.view.devicePixelRatio);
    await tester.pumpAndSettle();

    router.pushReplacement('/play/e5');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(backdrop('player e5').color, Colors.black);
    await tester.pumpAndSettle();
    expect(find.text('player e5'), findsOneWidget);
    expect(find.text('player e4'), findsNothing);
  });
}
