import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/calendar/calendar_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../support/fake_session_controller.dart';
import '../support/home_fakes.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

void main() {
  const signedIn = SessionSignedIn(testUser);

  test('avvio: tutto porta allo splash', () {
    expect(sessionRedirect(const SessionStarting(), '/home'),
        '/splash?from=%2Fhome');
    expect(sessionRedirect(signedIn, '/splash?from=%2Fhome'), '/home');
    expect(sessionRedirect(const SessionStarting(), '/splash'), isNull);
  });

  test("avvio da una pagina (tocco su una notifica): si apre dopo l'accesso",
      () {
    const target = '/admin?tab=downloads';
    final splash = sessionRedirect(const SessionStarting(), target)!;
    expect(Uri.parse(splash).path, '/splash');
    expect(sessionRedirect(const SessionStarting(), splash), isNull);
    expect(sessionRedirect(signedIn, splash), target);

    // Senza sessione passa per il login e "Chi guarda?".
    final login = sessionRedirect(const SessionSignedOut(), splash)!;
    expect(Uri.parse(login).path, '/login');
    final profiles = sessionRedirect(const SessionChoosingProfile(), login)!;
    expect(Uri.parse(profiles).path, '/profiles');
    expect(sessionRedirect(signedIn, profiles), target);
  });

  test('from non valido: Home', () {
    for (final from in [
      'https://evil.example/x',
      '//evil.example/x',
      r'/\evil.example',
      'admin',
      '/login',
    ]) {
      final splash = Uri(path: '/splash', queryParameters: {'from': from});
      expect(sessionRedirect(signedIn, splash.toString()), '/home',
          reason: from);
    }
  });

  test("uscita da una pagina: dopo l'accesso la Home", () {
    expect(sessionRedirect(const SessionSignedOut(), '/settings'), '/login');
    expect(sessionRedirect(signedIn, '/login'), '/home');
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

  testWidgets('avvio a freddo su /admin?tab=downloads con la sessione '
      'salvata: resta lì', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/admin?tab=downloads';
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    final session = FakeSessionController(const SessionStarting());
    late GoRouter router;
    await pumpAppRouterOf(tester, (ref) => router = ref.watch(routerProvider),
        overrides: [
          ...homeOverrides(library: FakeLibraryApi(), session: session),
          watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
          syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
          watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        ]);
    String location() =>
        router.routerDelegate.currentConfiguration.uri.toString();
    expect(Uri.parse(location()).path, '/splash');

    session.set(const SessionSignedIn(
        JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true)));
    await tester.pump();
    expect(location(), '/admin?tab=downloads');
    // Smonta l'app: l'amministrazione interroga il server di continuo.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('/calendar?month=2026-11 apre il calendario di novembre',
      (tester) async {
    late GoRouter router;
    await pumpAppRouterOf(tester, (ref) => router = ref.watch(routerProvider),
        overrides: [
          ...homeOverrides(
            library: FakeLibraryApi(),
            features: const SocialFeatures(calendar: true),
          ),
          watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
          syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
          watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        ]);
    router.go('/calendar?month=2026-11');
    await tester.pumpAndSettle();

    expect(
        tester.widget<CalendarScreen>(find.byType(CalendarScreen)).month,
        DateTime(2026, 11));
  });
}
