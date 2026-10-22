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
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeRequestsApi api;
  late StreamController<SocialEvent> events;

  /// Le funzioni del plugin: da qui si toglie `requests` mentre la pagina è
  /// aperta.
  late FakeSocialAvailability availability;
  const manager = RequestsMe(canRequest: true, canManage: true, hasAccount: true);

  setUp(() {
    api = FakeRequestsApi();
    events = StreamController<SocialEvent>.broadcast();
    availability = FakeSocialAvailability(const SocialFeatures(requests: true));
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
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/tmdb/:type/:tmdbId',
          builder: (context, state) =>
              Scaffold(body: Text('scheda ${state.pathParameters['tmdbId']}')),
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
        socialAvailabilityProvider.overrideWith(() => availability),
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

  testWidgets('se un ricaricamento accorcia l\'elenco, carica ancora le altre',
      (tester) async {
    api.lists[RequestsFilter.mine] = [
      for (var i = 1; i <= 25; i++) testMediaRequest(id: i, title: 'Titolo $i'),
    ];
    await pumpScreen(tester, surfaceSize: const Size(1440, 4000));
    expect(api.calls.where((c) => c == 'list:mine:20:20'), hasLength(1));

    // L'elenco riparte da venti righe, che ancora non riempiono la finestra.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RequestsScreen)));
    await container
        .read(requestsListControllerProvider(
                (filter: RequestsFilter.mine, language: 'it'))
            .notifier)
        .reload();
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c == 'list:mine:20:20'), hasLength(2));
    expect(find.text('Titolo 25 (2024)'), findsOneWidget);
  });

  group('senza la funzione', () {
    testWidgets('tolta mentre si guarda la pagina, torna alla Home',
        (tester) async {
      api.lists[RequestsFilter.mine] = [
        testMediaRequest(id: 1, title: 'Dune', year: 2021),
      ];
      final router = await pumpScreen(tester);
      expect(find.text('Dune (2021)'), findsOneWidget);

      // Seerr tolto dal plugin: le funzioni sono note e senza `requests`.
      availability.set(const SocialFeatures());
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/home');
      expect(find.text('home'), findsOneWidget);
      expect(find.text('Riprova'), findsNothing);
    });

    testWidgets('aperta senza la funzione, va subito alla Home',
        (tester) async {
      availability = FakeSocialAvailability(const SocialFeatures());
      final router = await pumpScreen(tester);

      expect(router.state.uri.path, '/home');
      expect(find.text('home'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('finché le funzioni non sono note, la pagina resta',
        (tester) async {
      api.lists[RequestsFilter.mine] = [
        testMediaRequest(id: 1, title: 'Dune', year: 2021),
      ];
      final router = await pumpScreen(tester);

      availability.set(SocialFeatures.unknown);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/requests');
      expect(find.text('Dune (2021)'), findsOneWidget);

      availability.set(const SocialFeatures(requests: true));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/requests');
      expect(find.text('Dune (2021)'), findsOneWidget);
    });
  });

  group('Da approvare', () {
    setUp(() {
      api
        ..meValue = manager
        ..lists[RequestsFilter.pending] = [
          testMediaRequest(id: 1, title: 'Dune', requester: 'Garg'),
          testMediaRequest(id: 2, title: 'Brothers', requester: 'sronweb'),
        ]
        ..servicesByType[RequestMediaType.movie] = const [
          ServiceOption(
            id: 0,
            name: 'Radarr',
            isDefault: true,
            profiles: [ProfileOption(id: 8, name: 'Main Profile')],
            rootFolders: ['/media/movies'],
          ),
        ];
    });

    testWidgets('Approva: finestra, poi la riga esce e c\'è l\'avviso',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Approva').first);
      await tester.pumpAndSettle();
      expect(find.text('Approva: Dune'), findsOneWidget);

      await tester.tap(find.text('Approva').last);
      await tester.pumpAndSettle();

      expect(api.approved.single.id, 1);
      expect(api.approved.single.choice.serverId, isNull);
      expect(find.text('Dune (2024)'), findsNothing);
      expect(find.text('Brothers (2024)'), findsOneWidget);
      expect(find.text('Approvata'), findsOneWidget);
    });

    testWidgets('durante Approva, locandina e titolo della riga non aprono niente',
        (tester) async {
      final gate = api.actionGate = Completer<void>();
      final router = await pumpScreen(tester);

      await tester.tap(find.text('Approva').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approva').last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final dune = find.byKey(const ValueKey('request-1'));
      await tester.tap(find.text('Dune (2024)'));
      await tester.tap(find.descendant(of: dune, matching: find.byType(ClipRRect)));
      await tester.pump();
      expect(router.state.uri.path, '/requests');

      // L'altra riga si apre come sempre.
      await tester.tap(find.text('Brothers (2024)'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/tmdb/movie/693002');

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Rifiuta con conferma', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Rifiuta').last);
      await tester.pump();
      await tester.tap(find.text('Conferma'));
      await tester.pump();
      await tester.pump();

      expect(api.declined, [2]);
      expect(find.text('Brothers (2024)'), findsNothing);
      expect(find.text('Rifiutata'), findsOneWidget);
    });

    testWidgets('un errore lascia la riga e lo dice', (tester) async {
      api.actionFailure = RequestsFailure.seerrUnavailable;
      await pumpScreen(tester);

      await tester.tap(find.text('Rifiuta').first);
      await tester.pump();
      await tester.tap(find.text('Conferma'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Dune (2024)'), findsOneWidget);
      expect(find.text('Non riuscito, riprova'), findsOneWidget);
    });

    testWidgets('durante Approva la riga mostra solo l\'indicatore, poi esce',
        (tester) async {
      final gate = api.actionGate = Completer<void>();
      await pumpScreen(tester);

      await tester.tap(find.text('Approva').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approva').last);
      // L'indicatore gira: niente `pumpAndSettle` finché la risposta non arriva.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final dune = find.byKey(const ValueKey('request-1'));
      final brothers = find.byKey(const ValueKey('request-2'));
      expect(api.approved.single.id, 1);
      expect(find.descendant(of: dune, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      // I pulsanti tengono il posto ma non si vedono.
      expect(
        tester
            .widget<Visibility>(find.descendant(
                of: dune, matching: find.byType(Visibility)))
            .visible,
        isFalse,
      );
      // L'altra riga resta com'era.
      expect(find.descendant(of: brothers, matching: find.byType(CircularProgressIndicator)),
          findsNothing);
      expect(
        tester
            .widget<Visibility>(find.descendant(
                of: brothers, matching: find.byType(Visibility)))
            .visible,
        isTrue,
      );

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Dune (2024)'), findsNothing);
      expect(find.text('Brothers (2024)'), findsOneWidget);
      expect(find.text('Approvata'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
