import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
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

  test('più profili: "Chi guarda?", con il login per aggiungerne uno', () {
    expect(sessionRedirect(const SessionChoosingProfile(), '/home'),
        '/profiles');
    expect(sessionRedirect(const SessionChoosingProfile(), '/profiles'),
        isNull);
    expect(sessionRedirect(const SessionSignedOut(adding: true), '/profiles'),
        '/login');
    // Scelto un profilo si va alla Home.
    expect(sessionRedirect(signedIn, '/profiles'), '/home');
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

  /// Con [full] l'app è in movimento completo (`WfMotionScope`); senza, è
  /// ridotto come nei test che montano l'app a mano.
  Future<void> pumpRouter(WidgetTester tester, GoRouter router,
          {bool full = false}) =>
      tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        builder: full
            ? (context, child) => WfMotionScope(
                motion: const WfMotion(MotionLevel.full), child: child!)
            : null,
      ));

  /// Opacità della dissolvenza della pagina che mostra [text].
  double pageOpacity(WidgetTester tester, String text) =>
      tester
          .widget<FadeTransition>(find.ancestor(
              of: find.text(text), matching: find.byType(FadeTransition)))
          .opacity
          .value;

  testWidgets('player: entra in medium, esce in fast (movimento completo)',
      (tester) async {
    final router = playerTestRouter();
    await pumpRouter(tester, router, full: true);

    router.push('/play/e4');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(WfMotion.fast);
    expect(pageOpacity(tester, 'player e4'), lessThan(1),
        reason: 'dopo fast sta ancora entrando');
    await tester.pump(WfMotion.medium - WfMotion.fast);
    expect(pageOpacity(tester, 'player e4'), 1);
    await tester.pumpAndSettle();

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(WfMotion.fast ~/ 2);
    expect(pageOpacity(tester, 'player e4'), allOf(greaterThan(0), lessThan(1)),
        reason: 'a metà di fast sta ancora uscendo');
    await tester.pump(WfMotion.fast ~/ 2);
    await tester.pump();
    expect(find.text('player e4'), findsNothing,
        reason: 'esce in fast, non in medium');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('player: movimento ridotto, entra in fast', (tester) async {
    final router = playerTestRouter();
    await pumpRouter(tester, router);

    router.push('/play/e4');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(WfMotion.fast ~/ 2);
    expect(pageOpacity(tester, 'player e4'), lessThan(1));
    await tester.pump(WfMotion.fast ~/ 2);
    expect(pageOpacity(tester, 'player e4'), 1,
        reason: 'ridotto: tutto il movimento dura fast');
    await tester.pumpAndSettle();
  });

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
