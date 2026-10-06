import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';
import 'package:wonderflix/features/admin/admin_screen.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/states.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdminApi api;

  setUp(() {
    api = FakeAdminApi()
      ..sessionsValue = testSessions()
      ..partiesValue = testParties();
  });

  /// Durata della transizione verso `/login` nel test del logout: finché
  /// dura, la pagina vecchia resta montata, come in un cambio di pagina vero.
  const loginTransition = Duration(milliseconds: 300);

  /// La pagina in un router con `/admin` e `/home`, come nell'app. Con
  /// [withSessionRedirect] il router segue la sessione come quello vero
  /// (`/login` con una transizione lenta). Con [availability] le funzioni del
  /// plugin si cambiano durante il test; con [settle] falso si fanno solo
  /// pochi `pump` (serve quando c'è un indicatore che non si ferma).
  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    required FakeSessionController session,
    String location = '/admin',
    bool withSessionRedirect = false,
    SocialFeatures features = const SocialFeatures(inbox: true),
    FakeSocialAvailability? availability,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sessionState = ValueNotifier<SessionState>(session.initial);
    addTearDown(sessionState.dispose);
    final router = GoRouter(
      initialLocation: location,
      refreshListenable: withSessionRedirect ? sessionState : null,
      redirect: withSessionRedirect
          ? (context, state) =>
              sessionRedirect(sessionState.value, state.matchedLocation)
          : null,
      routes: [
        if (withSessionRedirect)
          GoRoute(
            path: '/login',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: loginTransition,
              child: const Scaffold(body: Text('login')),
              transitionsBuilder: (context, animation, _, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
        GoRoute(
          path: '/admin',
          builder: (context, state) => Scaffold(
            body: AdminScreen(
                tab: AdminTab.parse(state.uri.queryParameters['tab'])),
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: Text('home')),
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
        ...adminTestOverrides(api,
            session: session,
            features: features,
            availability: availability),
      ],
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    if (withSessionRedirect) {
      final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)));
      container.listen(sessionControllerProvider,
          (_, next) => sessionState.value = next);
    }
    return router;
  }

  testWidgets('admin: titolo, striscia, scheda Sessioni', (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)));

    expect(find.text('AMMINISTRAZIONE'), findsOneWidget);
    // Il nome del server nella striscia e la scheda.
    expect(find.text('WonderFlix'), findsNWidgets(2));
    expect(find.text('Jellyfin 10.11.9'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-tab-sessions')), findsOneWidget);
    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('scheda sconosciuta nell\'indirizzo: Sessioni', (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        location: '/admin?tab=boh');

    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('non admin: torna alla Home senza chiamare Jellyfin',
      (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testUser)));

    expect(find.text('home'), findsOneWidget);
    expect(find.text('Non sei più amministratore'), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('non più admin mentre guarda la pagina: avviso e Home',
      (tester) async {
    final session = FakeSessionController(const SessionSignedIn(testAdmin));
    await pumpScreen(tester, session: session);

    session.set(const SessionSignedIn(testUser));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('home'), findsOneWidget);
    expect(find.text('Non sei più amministratore'), findsOneWidget);
  });

  testWidgets('logout sulla pagina: Login, senza avviso né Home',
      (tester) async {
    final session = FakeSessionController(const SessionSignedIn(testAdmin));
    await pumpScreen(tester, session: session, withSessionRedirect: true);
    expect(find.text('viviroby'), findsOneWidget);

    session.set(const SessionSignedOut());
    // La pagina vecchia resta montata per tutta la transizione.
    await tester.pump();
    await tester.pump(loginTransition ~/ 2);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('login'), findsOneWidget);
    expect(find.text('Non sei più amministratore'), findsNothing);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('quattro schede; un clic cambia scheda nell\'indirizzo',
      (tester) async {
    final router = await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)));

    for (final tab in ['sessions', 'maintenance', 'activity', 'wonderflix']) {
      expect(find.byKey(ValueKey('admin-tab-$tab')), findsOneWidget);
    }

    await tester.tap(find.text('Manutenzione'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin?tab=maintenance');
    expect(find.text('Librerie'), findsOneWidget);

    await tester.tap(find.text('Registro'));
    await tester.pumpAndSettle();
    expect(find.text('Aggiorna'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-tab-wonderflix')));
    await tester.pumpAndSettle();
    expect(find.text('Annuncio'), findsOneWidget);
  });

  testWidgets('senza la cassetta del plugin: niente WonderFlix, si mostra '
      'Sessioni', (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        location: '/admin?tab=wonderflix',
        features: SocialFeatures.none);

    expect(find.byKey(const ValueKey('admin-tab-wonderflix')), findsNothing);
    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('funzioni del plugin non ancora note: WonderFlix aspetta, senza '
      'passare da Sessioni', (tester) async {
    final availability = FakeSocialAvailability(SocialFeatures.unknown);
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        location: '/admin?tab=wonderflix',
        availability: availability,
        settle: false);

    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.text('viviroby'), findsNothing);
    expect(api.count('sessions'), 0, reason: 'Sessioni non si legge per niente');

    availability.set(const SocialFeatures(inbox: true));
    await tester.pumpAndSettle();

    expect(find.byType(LoadingView), findsNothing);
    expect(find.byKey(const ValueKey('admin-tab-wonderflix')), findsOneWidget);
    expect(find.text('Annuncio'), findsOneWidget);
    expect(api.count('sessions'), 0);
  });

  testWidgets('funzioni non note e poi senza cassetta: si mostra Sessioni',
      (tester) async {
    final availability = FakeSocialAvailability(SocialFeatures.unknown);
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        location: '/admin?tab=wonderflix',
        availability: availability,
        settle: false);
    expect(find.byType(LoadingView), findsOneWidget);

    availability.set(SocialFeatures.none);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('admin-tab-wonderflix')), findsNothing);
    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('funzioni non note: le altre schede si vedono subito',
      (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        availability: FakeSocialAvailability(SocialFeatures.unknown));

    expect(find.text('viviroby'), findsOneWidget);
  });
}
