import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
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

  GoRouter playerTestRouter() {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/play/:id',
        pageBuilder: (context, state) => playerPage(
            context, state, Text('player ${state.pathParameters['id']}')),
      ),
    ]);
    addTearDown(router.dispose);
    return router;
  }

  testWidgets('player dalla Home: dissolvenza incrociata, senza nero',
      (tester) async {
    final router = playerTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.push('/play/e4');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const Key('player-replacement-backdrop')), findsNothing);
    expect(find.text('home'), findsOneWidget,
        reason: 'la pagina di partenza resta sotto mentre il player sfuma');
    await tester.pumpAndSettle();
    expect(find.text('player e4'), findsOneWidget);
  });

  testWidgets('player che ne sostituisce un altro: sotto solo nero',
      (tester) async {
    final router = playerTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/play/e4');
    await tester.pumpAndSettle();

    router.pushReplacement('/play/e5', extra: playerReplacement);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final backdrop = find.byKey(const Key('player-replacement-backdrop'));
    expect(tester.widget<ColoredBox>(backdrop).color, Colors.black);
    expect(tester.getSize(backdrop),
        tester.view.physicalSize / tester.view.devicePixelRatio);
    await tester.pumpAndSettle();
    expect(find.text('player e5'), findsOneWidget);
    expect(find.text('player e4'), findsNothing);
  });

  testWidgets('player sostituito che si chiude: sfuma sulla pagina, no nero',
      (tester) async {
    final router = playerTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/play/e4');
    await tester.pumpAndSettle();
    router.pushReplacement('/play/e5', extra: playerReplacement);
    await tester.pumpAndSettle();
    final backdrop = find.byKey(const Key('player-replacement-backdrop'));
    expect(tester.widget<ColoredBox>(backdrop).color, Colors.black,
        reason: 'a transizione finita il nero resta');

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<ColoredBox>(backdrop).color, Colors.transparent,
        reason: 'in uscita il nero non copre la pagina sotto');
    expect(find.text('home'), findsOneWidget);
    expect(find.text('player e5'), findsOneWidget,
        reason: 'il player sfuma, non sparisce di colpo');
    await tester.pumpAndSettle();
    expect(find.text('player e5'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
