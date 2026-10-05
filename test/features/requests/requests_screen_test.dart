import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/requests/requests_list_controller.dart';
import 'package:wonderflix/features/requests/requests_navigation.dart';
import 'package:wonderflix/features/requests/requests_screen.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;
  late StreamController<SocialEvent> events;
  const manager = RequestsMe(canRequest: true, canManage: true, hasAccount: true);

  setUp(() {
    api = FakeRequestsApi();
    events = StreamController<SocialEvent>.broadcast();
  });

  tearDown(() => events.close());

  /// Monta la pagina dentro un router con la rotta `/requests`, come nell'app:
  /// la scheda scelta sta nell'indirizzo, e la pagina si rifà a ogni
  /// indirizzo nuovo.
  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    String location = '/requests',
    Size surfaceSize = const Size(1440, 900),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/requests',
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: Scaffold(
              body: RequestsScreen(
                key: ValueKey(state.uri.toString()),
                initialTab: RequestsTab.parse(state.uri.queryParameters['tab']),
              ),
            ),
          ),
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
        ...requestsTestOverrides(api, events: events.stream),
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

  testWidgets('utente normale: le sue richieste, senza schede', (tester) async {
    api.lists[RequestsFilter.mine] = [
      testMediaRequest(id: 1, title: 'Dune', year: 2021, status: RequestStatus.approved),
    ];
    await pumpScreen(tester);

    expect(find.text('RICHIESTE'), findsOneWidget);
    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text('Approvata'), findsOneWidget);
    expect(find.text('Le mie'), findsNothing);
    expect(find.textContaining('chiesto da'), findsNothing);
    expect(api.calls.where((c) => c.startsWith('list:pending')), isEmpty);
  });

  testWidgets('admin con richieste in attesa: si apre su "Da approvare (2)"',
      (tester) async {
    api
      ..meValue = manager
      ..lists[RequestsFilter.pending] = [
        testMediaRequest(id: 1, title: 'Dune', requester: 'Garg'),
        testMediaRequest(id: 2, title: 'Brothers', requester: 'sronweb'),
      ]
      ..lists[RequestsFilter.mine] = [testMediaRequest(id: 3, title: 'Mia')];
    await pumpScreen(tester);

    expect(find.text('Da approvare (2)'), findsOneWidget);
    expect(find.text('Le mie'), findsOneWidget);
    expect(find.text('Tutte'), findsOneWidget);
    expect(find.textContaining('chiesto da Garg'), findsOneWidget);
    expect(find.text('Mia (2024)'), findsNothing);

    await tester.tap(find.text('Le mie'));
    await tester.pumpAndSettle();

    expect(find.text('Mia (2024)'), findsOneWidget);
    expect(find.textContaining('chiesto da'), findsNothing);
  });

  testWidgets('admin senza richieste in attesa: si apre su "Le mie"',
      (tester) async {
    api.meValue = manager;
    await pumpScreen(tester);

    expect(find.text('Da approvare (0)'), findsOneWidget);
    expect(find.text('Non hai ancora chiesto niente. Cerca un titolo che manca e premi Richiedi.'),
        findsOneWidget);
  });

  testWidgets('scheda dall\'indirizzo e pagine vuote', (tester) async {
    api.meValue = manager;
    await pumpScreen(tester, location: '/requests?tab=all');
    expect(find.text('Nessuna richiesta'), findsOneWidget);

    await tester.tap(find.text('Da approvare (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Niente da approvare'), findsOneWidget);
  });

  testWidgets('la scheda scelta sta nell\'indirizzo, e un link alla stessa '
      'scheda di prima la riapre', (tester) async {
    api
      ..meValue = manager
      ..lists[RequestsFilter.pending] = [testMediaRequest(id: 1, title: 'Dune')];
    final router = await pumpScreen(tester, location: '/requests?tab=pending');
    expect(find.text('Dune (2024)'), findsOneWidget);

    await tester.tap(find.text('Tutte'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/requests?tab=all');
    expect(find.text('Nessuna richiesta'), findsOneWidget);

    // Come "Nuova richiesta" nella cassetta: non resta sulla scheda "Tutte".
    router.go('/requests?tab=pending');
    await tester.pumpAndSettle();
    expect(find.text('Dune (2024)'), findsOneWidget);
    expect(find.text('Nessuna richiesta'), findsNothing);
  });

  testWidgets('la scheda scelta da sola non cambia quando cambia il conteggio',
      (tester) async {
    api
      ..meValue = manager
      ..lists[RequestsFilter.pending] = [testMediaRequest(id: 1, title: 'Dune')];
    await pumpScreen(tester);
    expect(find.text('Da approvare (1)'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RequestsScreen)));

    // Si approva l'ultima richiesta: il conteggio va a 0, ma la pagina resta
    // dov'è.
    api.lists[RequestsFilter.pending] = [];
    await container
        .read(requestsListControllerProvider(
                (filter: RequestsFilter.pending, language: 'it'))
            .notifier)
        .decline(1);
    await tester.pumpAndSettle();

    expect(find.text('Da approvare (0)'), findsOneWidget);
    expect(find.text('Niente da approvare'), findsOneWidget);
  });

  testWidgets('arriva una richiesta mentre si guarda "Le mie": la pagina resta',
      (tester) async {
    api.meValue = manager;
    await pumpScreen(tester);
    expect(find.text('Da approvare (0)'), findsOneWidget);

    api.lists[RequestsFilter.pending] = [testMediaRequest(id: 1, title: 'Dune')];
    events.add(const InboxChangedEvent());
    await tester.pumpAndSettle();

    expect(find.text('Da approvare (1)'), findsOneWidget);
    expect(find.text('Non hai ancora chiesto niente. Cerca un titolo che manca e premi Richiedi.'),
        findsOneWidget);
    expect(find.text('Dune (2024)'), findsNothing);
  });

  testWidgets('errore e Riprova', (tester) async {
    api.failure = RequestsFailure.network;
    await pumpScreen(tester);
    expect(find.text('Riprova'), findsOneWidget);

    api
      ..failure = null
      ..lists[RequestsFilter.mine] = [testMediaRequest(id: 1, title: 'Dune', year: 2021)];
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.text('Dune (2021)'), findsOneWidget);
  });

  testWidgets('scorrendo in fondo carica le altre', (tester) async {
    api.lists[RequestsFilter.mine] = [
      for (var i = 1; i <= 25; i++) testMediaRequest(id: i, title: 'Titolo $i'),
    ];
    await pumpScreen(tester);
    expect(api.calls, isNot(contains('list:mine:20:20')));

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump();

    expect(api.calls, contains('list:mine:20:20'));
  });

  testWidgets('se le righe non riempiono la finestra, carica le altre da sole',
      (tester) async {
    api.lists[RequestsFilter.mine] = [
      for (var i = 1; i <= 25; i++) testMediaRequest(id: i, title: 'Titolo $i'),
    ];
    // Una finestra alta: venti righe non bastano a farla scorrere.
    await pumpScreen(tester, surfaceSize: const Size(1440, 4000));

    expect(api.calls, contains('list:mine:20:20'));
    expect(find.text('Titolo 25 (2024)'), findsOneWidget);
  });
}
