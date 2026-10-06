import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';
import 'package:wonderflix/features/admin/admin_screen.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdminApi api;

  setUp(() {
    api = FakeAdminApi()
      ..sessionsValue = testSessions()
      ..partiesValue = testParties();
  });

  /// La pagina in un router con `/admin` e `/home`, come nell'app.
  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    required FakeSessionController session,
    String location = '/admin',
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: location,
      routes: [
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
        ...adminTestOverrides(api, session: session),
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
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('admin: titolo, striscia, scheda Sessioni', (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)));

    expect(find.text('AMMINISTRAZIONE'), findsOneWidget);
    expect(find.text('WonderFlix'), findsOneWidget);
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
}
