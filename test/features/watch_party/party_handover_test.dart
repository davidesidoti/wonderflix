import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/player_volume.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_routing.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

/// Routing del watch party e player insieme, con il `GoRouter` vero: il
/// cambio di episodio del gruppo lascia un solo player.
void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;
  late GoRouter router;
  late FakeLibraryApi library;
  late FakePlayerWindow window;
  late FakeMediaSession mediaSession;

  /// Motori dei player, in ordine di apertura.
  late List<FakeVideoEngine> engines;

  void emit(GroupUpdate update) => events.add(SyncPlayGroupUpdated(update));

  JellyfinItem episode(String id, int index) => testItem(
        id: id,
        name: 'Episodio $index',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: index,
        seasonIndex: 1,
      );

  /// Home con il routing del watch party attivo; l'utente entra nel gruppo
  /// `g1`, che guarda la serie (e4, poi e5 ed e6).
  Future<void> pumpApp(WidgetTester tester, {bool join = true}) async {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    final playback = FakePlaybackApi();
    library = FakeLibraryApi()
      ..itemsById['e4'] = episode('e4', 4)
      ..itemsById['e5'] = episode('e5', 5)
      ..itemsById['e6'] = episode('e6', 6);
    window = FakePlayerWindow();
    mediaSession = FakeMediaSession();
    engines = [];
    router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/play/:id',
        builder: (context, state) => PlayerScreen(
          key: ValueKey(state.uri.toString()),
          args: (
            itemId: state.pathParameters['id']!,
            start: playerStartFrom(state.uri),
            party: state.uri.queryParameters['party'],
          ),
          fullscreen: state.uri.queryParameters['fs'] == '1',
        ),
      ),
    ]);
    addTearDown(router.dispose);
    container = ProviderContainer(
      overrides: [
        routerProvider.overrideWithValue(router),
        libraryApiProvider.overrideWithValue(library),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(PlaybackService(
          api: playback,
          serverUrl: testServerUrl,
          authorization: () => 'MediaBrowser Token="t1"',
        )),
        videoEngineFactoryProvider.overrideWithValue(() {
          final engine = FakeVideoEngine()..engineTracks = testEngineTracks;
          engines.add(engine);
          return engine;
        }),
        playerWindowProvider.overrideWithValue(window),
        mediaSessionProvider.overrideWithValue(mediaSession),
        playerSettingsProvider
            .overrideWith(() => FakePlayerSettings(const PlayerSettings())),
        playerVolumeProvider.overrideWith(FakePlayerVolume.new),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        appConfigProvider.overrideWithValue(testAppConfig),
        imageBuilderProvider.overrideWithValue(
            (image, fit) => const ColoredBox(color: Color(0xFF333333))),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
      ],
      retry: (_, _) => null,
    );
    // Come `WonderflixApp`: il routing ascolta la sessione prima del player.
    container.listen(watchPartyRoutingProvider, (_, _) {});
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    if (join) {
      api.onCall = (call) {
        if (call.startsWith('join')) {
          emit(GroupJoined('g1', testGroup(participants: ['Mario', 'Luigi'])));
        }
      };
      unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
      await tester.pump();
      await tester.pump();
    }
  }

  /// Smonta tutto: chiude il player, ferma l'orologio del gruppo e lascia
  /// scadere i timer.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    container.dispose();
    await tester.pump();
  }

  List<String> pages() => [
        for (final match in router.routerDelegate.currentConfiguration.matches)
          match.matchedLocation,
      ];

  testWidgets(
      'il gruppo passa all\'episodio dopo: un solo player, sopra la Home',
      (tester) async {
    await pumpApp(tester);
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/play/e4?party=p1');
    expect(pages(), ['/home', '/play/e4']);

    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 1,
            reason: 'NextItem',
            lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/play/e5?party=p2');
    expect(pages(), ['/home', '/play/e5'],
        reason: 'il player vecchio non resta sotto quello nuovo');
    expect(find.byType(PlayerScreen, skipOffstage: false), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
      '"Guarda insieme" dal player: stesso punto nel gruppo, schermo intero '
      'com\'è, un solo player', (tester) async {
    await pumpApp(tester, join: false);
    library.seriesEpisodes['s1'] = [
      episode('e4', 4),
      episode('e5', 5),
      episode('e6', 6),
    ];
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schermo intero'));
    await tester.pump();
    expect(window.fullScreenCalls, [true]);
    engines.single.emitPosition(const Duration(minutes: 12));
    await tester.pump();

    api.onCall = (call) {
      if (call.startsWith('create')) {
        emit(GroupJoined('g1', testGroup(participants: ['Mario'])));
      }
      if (call.startsWith('queue')) {
        emit(PlayQueueUpdate('g1', testSeriesQueue()));
      }
    };
    await tester.tap(find.byTooltip('Guarda insieme'));
    await tester.pumpAndSettle();

    expect(api.calls.take(2), ['create Mario · Breaking Bad', 'queue e4,e5,e6']);
    expect(api.queues.last.start, const Duration(minutes: 12),
        reason: 'il gruppo parte dal minuto del player da solo');
    expect(router.state.uri.toString(), '/play/e4?fs=1&party=p1');
    expect(find.byType(PlayerScreen, skipOffstage: false), findsOneWidget);
    expect(window.fullScreenCalls, [true],
        reason: 'il player sostituito non esce dallo schermo intero');
    await finish(tester);
  });

  testWidgets(
      'nel gruppo senza coda con un player da solo aperto: arriva la coda, il '
      'player sostituito non esce dallo schermo intero né nasconde il '
      'pannello media', (tester) async {
    await pumpApp(tester);
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schermo intero'));
    await tester.pump();
    expect(window.fullScreenCalls, [true]);

    // Un altro membro sceglie cosa guardare.
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/play/e4?fs=1&party=p1');
    expect(find.byType(PlayerScreen, skipOffstage: false), findsOneWidget);
    expect(window.fullScreenCalls, [true]);
    expect(mediaSession.cleared, 0);
    expect(mediaSession.parties.last, 2,
        reason: 'Discord mostra il gruppo del player nuovo');
    await finish(tester);
  });

  testWidgets(
      '"Guarda insieme", poi uscita prima che arrivi la coda: uscita normale',
      (tester) async {
    await pumpApp(tester, join: false);
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schermo intero'));
    await tester.pump();

    // Il gruppo nasce, ma la coda non arriva.
    api.onCall = (call) {
      if (call.startsWith('create')) {
        emit(GroupJoined('g1', testGroup(participants: ['Mario'])));
      }
    };
    await tester.tap(find.byTooltip('Guarda insieme'));
    await tester.pumpAndSettle();
    expect(container.read(watchPartySessionProvider).inGroup, isTrue);

    await tester.tap(find.byTooltip(l.navBack));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(window.fullScreenCalls, [true, false]);
    expect(mediaSession.cleared, 1);
    expect(mediaSession.parties.last, isNull);
    await container.read(watchPartySessionProvider.notifier).leave();
    await finish(tester);
  });

  testWidgets(
      '"Guarda insieme" due volte di fila: un solo gruppo; il pulsante sparisce '
      'finché la richiesta è in corso', (tester) async {
    await pumpApp(tester, join: false);
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();

    // Il server non conferma: la richiesta resta in corso.
    api.onCall = null;
    await tester.tap(find.byTooltip('Guarda insieme'));
    await tester.tap(find.byTooltip('Guarda insieme'));
    await tester.pump();
    await tester.pump();
    expect(api.calls.where((call) => call.startsWith('create')), hasLength(1));
    expect(find.byTooltip('Guarda insieme'), findsNothing);

    // Nessuna conferma entro 10 s: errore, e il pulsante torna.
    await tester.pump(WatchPartySession.joinTimeout);
    await tester.pump();
    expect(find.byTooltip('Guarda insieme'), findsOneWidget);
    expect(api.calls.where((call) => call.startsWith('create')), hasLength(1));
    await finish(tester);
  });
}
