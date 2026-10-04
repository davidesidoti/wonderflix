import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_api.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/pause_screen.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_chrome.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/player_volume.dart';
import 'package:wonderflix/features/player/tracks_panel.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_chat_bubble.dart';
import 'package:wonderflix/features/watch_party/party_chat_layer.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/features/watch_party/party_reactions_layer.dart';
import 'package:wonderflix/features/watch_party/party_reactions_tray.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  /// Motore del primo player; ogni player dopo (episodio nuovo) ne ha uno.
  late FakeVideoEngine engine;
  late List<FakeVideoEngine> engines;
  late FakePlayerWindow window;
  late FakeMediaSession mediaSession;
  late FakeSyncPlayApi api;
  late FakePartyChannelApi channelApi;
  late StreamController<ServerEvent> events;
  late FakeLibraryApi library;
  late ProviderContainer container;
  late GoRouter router;

  void emit(GroupUpdate update) => events.add(SyncPlayGroupUpdated(update));

  /// Home con il player del watch party aperto sopra: l'utente è già nel
  /// gruppo `g1` (Mario e Luigi), che guarda `e4` (`p1`).
  Future<void> pumpPartyPlayer(WidgetTester tester,
      {int failOpens = 0,
      List<MediaSegment> segments = const [],
      bool plugin = true,
      bool queueFeature = true}) async {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    engine.failOpens = failOpens;
    engines = [];
    window = FakePlayerWindow();
    mediaSession = FakeMediaSession();
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    final playback = FakePlaybackApi();
    playback.segments = segments;
    library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(
        id: 'e4',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 4,
        seasonIndex: 1,
      )
      ..itemsById['e5'] = testItem(
        id: 'e5',
        name: 'Cat\'s in the Bag',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 5,
        seasonIndex: 1,
      )
      ..nextEpisodes['e4'] = testItem(
          id: 'e5', name: 'Cat\'s in the Bag', kind: ItemKind.episode);
    channelApi = FakePartyChannelApi();
    if (plugin) {
      channelApi.install(
          features: queueFeature ? const {partyQueueFeature} : const {});
    }
    router = GoRouter(routes: [
      GoRoute(
          path: '/',
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
        ),
      ),
    ]);
    addTearDown(router.dispose);
    container = ProviderContainer(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(PlaybackService(
          api: playback,
          serverUrl: testServerUrl,
          authorization: () => 'MediaBrowser Token="t1"',
        )),
        videoEngineFactoryProvider.overrideWithValue(() {
          final created = engines.isEmpty
              ? engine
              : (FakeVideoEngine()..engineTracks = testEngineTracks);
          engines.add(created);
          return created;
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
        partyChannelApiProvider.overrideWithValue(channelApi),
      ],
      retry: (_, _) => null,
    );
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
    api.onCall = (call) {
      if (call.startsWith('join')) {
        emit(GroupJoined(
            'g1', testGroup(participants: ['Mario', 'Luigi'])));
      }
    };
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pump();
    await tester.pump();
    unawaited(router.push(playerRoute('e4', party: 'p1')));
    await tester.pumpAndSettle();
  }

  /// Smonta tutto: chiude il player, ferma l'orologio del gruppo e lascia
  /// scadere i timer.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    container.dispose();
    await tester.pump();
  }

  SyncPlayCommand command(SyncPlayCommandType type) {
    final now = clock.now().toUtc();
    return SyncPlayCommand(
      groupId: 'g1',
      playlistItemId: 'p1',
      when: now,
      position: Duration.zero,
      type: type,
      emittedAt: now.add(const Duration(days: 365 * 100)),
    );
  }

  testWidgets('a file aperto: Ready al gruppo, il video non parte da solo',
      (tester) async {
    await pumpPartyPlayer(tester);
    expect(api.calls, contains('ready'));
    expect(engine.calls, isNot(contains('play')));
    await finish(tester);
  });

  testWidgets('il pulsante play chiede la ripresa al gruppo', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(api.calls, contains('unpause'));
    expect(engine.calls, isNot(contains('play')));
    await finish(tester);
  });

  testWidgets('il comando del gruppo fa partire il video', (tester) async {
    await pumpPartyPlayer(tester);
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.unpause)));
    await tester.pump();
    await tester.pump();
    expect(engine.calls, contains('play'));
    await finish(tester);
  });

  testWidgets('distintivo con i membri e uscita dal gruppo', (tester) async {
    await pumpPartyPlayer(tester);
    expect(find.text(l.watchPartyButton(2)), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('party-badge')), matching: find.text('M')),
        findsOneWidget,
        reason: 'le iniziali dei membri nel badge');
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    expect(find.text('Luigi'), findsOneWidget);
    await tester.tap(find.text(l.watchPartyLeave));
    await tester.pumpAndSettle();
    expect(api.calls, contains('leave'));
    expect(find.text('home'), findsOneWidget);
    expect(container.read(watchPartySessionProvider).inGroup, isFalse);
    await finish(tester);
  });

  testWidgets('attesa del gruppo: dopo 1 s, con "Riprendi senza aspettare"',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyWaiting), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l.watchPartyWaiting), findsOneWidget);
    await tester.tap(find.text(l.watchPartyResumeNow));
    await tester.pump();
    expect(api.calls, contains('unpause'));

    emit(const GroupStateUpdate('g1', GroupState.playing, 'Ready'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(); // l'attesa sfuma via
    expect(find.text(l.watchPartyWaiting), findsNothing);
    await finish(tester);
  });

  testWidgets('pausa del gruppo: "Stai guardando", ma non mentre aspetta',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(find.text(l.playerWatching.toUpperCase()), findsNothing);

    emit(const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
    await tester.pump();
    await tester.pump();
    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatching.toUpperCase()), findsOneWidget);
    await finish(tester);
  });

  testWidgets('nel watch party non c\'è l\'episodio successivo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.pump();
    expect(find.byTooltip(l.playerNextInQueue), findsNothing);
    await finish(tester);
  });

  testWidgets('gruppo chiuso dal server: il player continua da solo',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyButton(2)), findsNothing);
    expect(find.text(l.watchPartyNoticeRemoved), findsOneWidget);
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(engine.calls, contains('play'));
    await finish(tester);
  });

  /// Il gruppo guarda la serie: e4 (p1), poi e5 (p2) ed e6 (p3).
  Future<void> queueSeries(WidgetTester tester) async {
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    await tester.pump();
    await tester.pump();
  }

  /// La coda con un elemento prima: e3 (p0), e4 (p1, in riproduzione), e5.
  PlayQueue queueWithPrevious() => PlayQueue(
        reason: 'NewPlaylist',
        lastUpdate: DateTime.utc(2026, 9, 30, 10),
        entries: const [
          PlayQueueEntry(itemId: 'e3', playlistItemId: 'p0'),
          PlayQueueEntry(itemId: 'e4', playlistItemId: 'p1'),
          PlayQueueEntry(itemId: 'e5', playlistItemId: 'p2'),
        ],
        playingIndex: 1,
        startPosition: Duration.zero,
        isPlaying: false,
      );

  testWidgets('prossimo episodio: il pulsante lo chiede al gruppo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.playerNextInQueue));
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await finish(tester);
  });

  testWidgets('fine del video: episodio successivo per tutti', (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('next p1'));
    expect(find.byType(PlayerScreen), findsOneWidget,
        reason: 'nel gruppo il player non esce da solo');
    await finish(tester);
  });

  testWidgets('titoli di coda: scheda senza conto alla rovescia',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    // Senza segmenti la scheda compare negli ultimi 30 s (durata: 2 h).
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.playerNextEpisodeTitle.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Riproduci ora ·'), findsNothing);
    expect(find.text(l.playerPlayNow), findsOneWidget);
    // Sul pulsante, non sull'etichetta: sopra c'è lo strato dell'onda.
    await tester.tap(find.byType(PlayNowButton));
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await finish(tester);
  });

  testWidgets('titoli noti nel gruppo: post-play senza conto alla rovescia',
      (tester) async {
    await pumpPartyPlayer(tester, segments: const [
      MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration(hours: 1, minutes: 55),
          end: Duration(hours: 2)),
    ]);
    await queueSeries(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatchCredits), findsOneWidget);
    expect(find.textContaining('Riproduci ora ·'), findsNothing);
    expect(find.text(l.playerPlayNow), findsOneWidget);
    await tester.tap(find.byType(PlayNowButton));
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await finish(tester);
  });

  /// Titoli di coda noti di e4, dall'1:55:00.
  const credits = [
    MediaSegment(
        type: MediaSegmentType.outro,
        start: Duration(hours: 1, minutes: 55),
        end: Duration(hours: 2)),
  ];

  testWidgets(
      'titoli noti nel gruppo in pausa: arrivata la coda, il post-play prende '
      'il posto di "Stai guardando"', (tester) async {
    await pumpPartyPlayer(tester, segments: credits);
    // Il gruppo è in pausa (il video non è partito), nei titoli di coda.
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatching.toUpperCase()), findsOneWidget);
    expect(find.text(l.playerWatchCredits), findsNothing,
        reason: 'e5 non è ancora il prossimo della coda');

    await queueSeries(tester);
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatchCredits), findsOneWidget);
    expect(find.text(l.playerWatching.toUpperCase()), findsNothing,
        reason: 'niente schermata di pausa durante il post-play');
    await finish(tester);
  });

  testWidgets('post-play nel gruppo: tolti dal gruppo, compare il conto alla '
      'rovescia', (tester) async {
    await pumpPartyPlayer(tester, segments: credits);
    await queueSeries(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatchCredits), findsOneWidget);
    expect(find.textContaining('Riproduci ora ·'), findsNothing);

    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.playerWatchCredits), findsOneWidget,
        reason: 'il post-play resta');
    expect(find.textContaining('Riproduci ora ·'), findsOneWidget);
    await finish(tester);
  });

  /// Nei titoli di coda noti, con il post-play mostrato.
  Future<void> toCredits(WidgetTester tester) async {
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatchCredits), findsOneWidget);
  }

  testWidgets('attesa del gruppo durante il post-play: sta sopra, poi il '
      'post-play resta', (tester) async {
    await pumpPartyPlayer(tester, segments: credits);
    await queueSeries(tester);
    await toCredits(tester);
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l.watchPartyWaiting), findsOneWidget);
    // Sopra il post-play: un punto dell'immagine dell'episodio colpisce
    // l'attesa, non l'immagine.
    final waiting = tester.renderObject(find.byKey(const Key('party-waiting')));
    final image = tester.getCenter(find.byKey(const Key('post-play-image')));
    expect(
        tester
            .hitTestOnBinding(image)
            .path
            .any((entry) => entry.target == waiting),
        isTrue,
        reason: 'l\'attesa del gruppo copre il post-play');
    await tester.tap(find.text(l.watchPartyResumeNow));
    await tester.pump();
    expect(api.calls, contains('unpause'));

    emit(const GroupStateUpdate('g1', GroupState.playing, 'Ready'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(); // l'attesa sfuma via
    expect(find.text(l.watchPartyWaiting), findsNothing);
    expect(find.text(l.playerWatchCredits), findsOneWidget,
        reason: 'il post-play resta');
    await finish(tester);
  });

  testWidgets('post-play nel gruppo a video finito: chiuso, il player resta',
      (tester) async {
    await pumpPartyPlayer(tester, segments: credits);
    await queueSeries(tester);
    await toCredits(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await tester.tap(find.text(l.playerWatchCredits));
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatchCredits), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget,
        reason: 'uscire dal player vorrebbe dire lasciare il gruppo');
    expect(api.calls, isNot(contains('leave')));
    await finish(tester);
  });

  testWidgets(
      'il gruppo passa all\'episodio dopo: nuovo player a schermo intero, '
      'episodio lasciato sui titoli segnato come visto', (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.playerFullscreen));
    await tester.pump();
    expect(window.fullScreenCalls, [true]);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();

    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 1,
            reason: 'NextItem',
            lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await tester.pumpAndSettle();
    // Con push e pushReplacement la pagina attuale è in `router.state`.
    expect(router.state.uri.toString(), '/play/e5?fs=1&party=p2');
    expect(router.state.extra, isA<PlayerReplacement>(),
        reason: 'il nuovo player sostituisce il vecchio: transizione dal nero');
    expect(window.fullScreenCalls, [true],
        reason: 'passando all\'episodio dopo lo schermo intero resta');
    expect(library.playedCalls, contains(('e4', true)));
    expect(engines, hasLength(2));
    await finish(tester);
  });

  testWidgets(
      'salto in sospeso quando il gruppo cambia episodio: non arriva al '
      'gruppo (salterebbe nell\'episodio nuovo)', (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(engine.seeks, isNotEmpty);

    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 1,
            reason: 'NextItem',
            lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(router.state.uri.toString(), '/play/e5?party=p2');
    expect(api.calls.where((call) => call.startsWith('seek')), isEmpty);
    await finish(tester);
  });

  testWidgets('prossimo episodio con un salto in sospeso: solo NextItem',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(api.calls, contains('next p1'));
    await tester.pump(const Duration(seconds: 1));
    expect(api.calls.where((call) => call.startsWith('seek')), isEmpty);
    await finish(tester);
  });

  testWidgets('scheda "Prossimo episodio" solo se è il prossimo della coda',
      (tester) async {
    await pumpPartyPlayer(tester);
    // Nella coda del gruppo dopo e4 c'è e9, non e5 (il successivo nella
    // libreria).
    emit(PlayQueueUpdate('g1', testSeriesQueue(itemIds: ['e4', 'e9'])));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip(l.playerNextInQueue), findsOneWidget,
        reason: 'il pulsante segue la coda');
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.playerNextEpisodeTitle.toUpperCase()), findsNothing);
    await finish(tester);
  });

  testWidgets('"successivo" del pannello media: segue la coda del gruppo',
      (tester) async {
    await pumpPartyPlayer(tester);
    expect(mediaSession.nextEnabled, isNot(contains(true)),
        reason: 'e5 è il successivo nella libreria, ma non nella coda');
    await queueSeries(tester);
    expect(mediaSession.nextEnabled.last, isTrue);
    emit(PlayQueueUpdate(
        'g1',
        testQueue(
            itemId: 'e4', lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await tester.pump();
    await tester.pump();
    expect(mediaSession.nextEnabled.last, isFalse);
    await finish(tester);
  });

  testWidgets(
      'gruppo chiuso dal server: episodio successivo di nuovo da solo '
      '(pulsante, scheda con conto alla rovescia, fine del video)',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip(l.playerNextEpisode), findsOneWidget);
    expect(mediaSession.nextEnabled.last, isTrue);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Riproduci ora ·'), findsOneWidget);

    engine.emitCompleted();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/play/e5');
    expect(router.state.uri.queryParameters, isNot(contains('party')));
    expect(router.state.extra, isA<PlayerReplacement>());
    expect(api.calls, isNot(contains('next p1')));
    await finish(tester);
  });

  testWidgets('avvisi: pillola nel player, e le mie azioni in seconda persona',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
    await tester.pump();
    await tester.pump();
    // Con il canale del plugin attivo l'avviso altrui aspetta il nome; qui
    // l'annuncio non arriva ed esce senza (spec E §8).
    await tester.pump(PartyNotices.attributionWait);
    expect(find.text(l.watchPartyNoticePaused), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle(); // la pillola sfuma via
    expect(find.text(l.watchPartyNoticePaused), findsNothing);

    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(find.text(l.watchPartyNoticeResumedByYou), findsOneWidget);
    await finish(tester);
  });

  testWidgets('tasti nel watch party: la pillola del tasto, niente "Hai…"',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('unpause'));
    expect(find.text(l.playerFeedbackPlaying), findsOneWidget);
    expect(find.text(l.watchPartyNoticeResumedByYou), findsNothing);
    // Finito il riscontro del tasto la pillola non mostra l'avviso "Hai…"
    // che altrimenti resterebbe in coda.
    await tester.pump(PlayerChromeController.feedbackDuration);
    await tester.pumpAndSettle();
    expect(find.text(l.playerFeedbackPlaying), findsNothing);
    expect(find.text(l.watchPartyNoticeResumedByYou), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // Il salto parte verso il gruppo dopo 400 ms.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.textContaining('+10 s'), findsOneWidget);
    expect(find.textContaining('Hai saltato'), findsNothing);
    await tester.pump(PlayerChromeController.feedbackDuration);
    await tester.pumpAndSettle();
    expect(find.textContaining('+10 s'), findsNothing);
    expect(find.textContaining('Hai saltato'), findsNothing);
    await finish(tester);
  });

  testWidgets('riconnessione: rientro nel gruppo e Ready di nuovo',
      (tester) async {
    await pumpPartyPlayer(tester);
    final before = api.readyStates.length;
    events.add(const ServerConnected(true));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(api.calls.where((c) => c == 'join g1'), hasLength(2));
    expect(api.readyStates.length, before + 1);
    await finish(tester);
  });

  testWidgets('gruppo sparito al rientro: avviso e si continua da soli',
      (tester) async {
    await pumpPartyPlayer(tester);
    api.onCall = (call) {
      if (call.startsWith('join')) emit(const GroupDoesNotExist(''));
    };
    events.add(const ServerConnected(true));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyNoticeEnded), findsOneWidget);
    expect(find.text(l.watchPartyButton(2)), findsNothing);
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(engine.calls, contains('play'));
    await finish(tester);
  });

  testWidgets(
      'video che non si apre: il gruppo non aspetta, "Esci dal watch party"; '
      'Riprova riuscito torna nel gruppo', (tester) async {
    // Direct play e ripiego sulla transcodifica non riescono.
    await pumpPartyPlayer(tester, failOpens: 2);
    expect(find.text(l.playerErrorTitle), findsOneWidget);
    expect(api.calls, contains('ignore-wait true'));
    expect(find.text(l.watchPartyLeave), findsOneWidget);
    expect(find.text(l.playerBack), findsNothing);

    await tester.tap(find.text(l.retry));
    await tester.pumpAndSettle();
    final ignoreFalse = api.calls.indexOf('ignore-wait false');
    expect(ignoreFalse, greaterThanOrEqualTo(0));
    expect(api.calls.lastIndexOf('ready'), greaterThan(ignoreFalse));
    await finish(tester);
  });

  testWidgets(
      'video che non si apre, poi il gruppo passa all\'episodio dopo: aperto '
      'quello, il gruppo torna ad aspettarci prima del Ready', (tester) async {
    await pumpPartyPlayer(tester, failOpens: 2);
    await queueSeries(tester);
    expect(api.calls, contains('ignore-wait true'));
    api.calls.clear();

    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 1,
            reason: 'NextItem',
            lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/play/e5?party=p2');
    expect(engines, hasLength(2));
    expect(api.calls.where((c) => c.startsWith('ignore-wait') || c == 'ready'),
        ['ignore-wait false', 'ready']);
    await finish(tester);
  });

  testWidgets(
      'video che non si apre, poi una riconnessione: al rientro il gruppo di '
      'nuovo non ci aspetta', (tester) async {
    await pumpPartyPlayer(tester, failOpens: 2);
    expect(api.calls, contains('ignore-wait true'));
    api.calls.clear();

    events.add(const ServerConnected(true));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(api.calls, ['join g1', 'ignore-wait true'],
        reason: 'il server ricrea il membro senza l\'esclusione; nessun Ready '
            'con il video non aperto');
    expect(find.text(l.playerErrorTitle), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Discord: persone nel gruppo, niente fuori dal gruppo',
      (tester) async {
    await pumpPartyPlayer(tester);
    expect(mediaSession.parties.last, 2);
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(mediaSession.parties.last, isNull);
    await finish(tester);
  });

  List<Map<String, dynamic>> announced() => [
        for (final event in channelApi.sent)
          if (event is PartyOutgoingAction) event.toJson(),
      ];

  testWidgets('canale: la ripresa dal player si annuncia (spec E §7.4)',
      (tester) async {
    await pumpPartyPlayer(tester);
    expect(channelApi.calls, containsAllInOrder(['info', 'join g1']));
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(announced(), [
      {'Type': 'Action', 'Action': 'Unpause'},
    ]);
    await finish(tester);
  });

  testWidgets('canale: il prossimo episodio chiesto dall\'utente si annuncia',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.playerNextInQueue));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('next p1'));
    expect(announced(), [
      {'Type': 'Action', 'Action': 'NextItem'},
    ]);
    await finish(tester);
  });

  testWidgets('canale: l\'episodio dopo a fine video non si annuncia',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('next p1'));
    expect(announced(), isEmpty);
    await finish(tester);
  });

  Finder chatField() => find.byKey(const Key('party-chat-field'));

  Future<void> openChatWithEnter(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('chat: pulsante nel gruppo con il plugin, Invio la apre '
      '(spec E §9)', (tester) async {
    await pumpPartyPlayer(tester);
    expect(find.byTooltip(l.partyChatOpen), findsOneWidget);
    await openChatWithEnter(tester);
    expect(chatField(), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'party-chat');
    await finish(tester);
  });

  testWidgets('chat: senza plugin niente pulsante, Invio non fa nulla',
      (tester) async {
    await pumpPartyPlayer(tester, plugin: false);
    expect(find.byTooltip(l.partyChatOpen), findsNothing);
    await openChatWithEnter(tester);
    expect(chatField(), findsNothing);
    await finish(tester);
  });

  testWidgets('chat aperta: Spazio va al campo; Esc la chiude e i tasti '
      'tornano al player', (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.calls, isNot(contains('unpause')), reason: 'Spazio va al campo');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(chatField(), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget,
        reason: 'Esc chiude solo la chat');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.calls, contains('unpause'));
    await finish(tester);
  });

  testWidgets('chat aperta: il clic sul film la chiude senza mettere in pausa',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyChatOpen));
    await tester.pump();
    await tester.pump();
    expect(chatField(), findsOneWidget);
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(chatField(), findsNothing);
    expect(api.calls, isNot(contains('unpause')));
    await finish(tester);
  });

  testWidgets('chat e pannello "Audio e sottotitoli": uno alla volta',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyChatOpen));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip(l.playerAudioAndSubtitles));
    await tester.pumpAndSettle();
    expect(chatField(), findsNothing);
    expect(find.byType(TracksPanel), findsOneWidget);
    await finish(tester);
  });

  testWidgets('chat aperta: niente "Stai guardando"', (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    await tester.pump(PlayerChromeController.pauseScreenDelay +
        const Duration(seconds: 1));
    expect(tester.widget<PauseScreen>(find.byType(PauseScreen)).visible,
        isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(PlayerChromeController.pauseScreenDelay +
        const Duration(seconds: 1));
    expect(tester.widget<PauseScreen>(find.byType(PauseScreen)).visible,
        isTrue);
    await finish(tester);
  });

  testWidgets('chat: i messaggi arrivano come bolle, non come non letti',
      (tester) async {
    await pumpPartyPlayer(tester);
    events.add(PartyChannelReceived(
        partyPayload({'Type': 'Chat', 'Text': 'ciao a tutti'}, id: 'c1')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('ciao a tutti'), findsOneWidget);
    expect(find.byKey(const Key('player-chat-unread')), findsNothing);
    await finish(tester);
  });

  /// Messaggio di Luigi dal canale.
  Future<void> receiveChat(WidgetTester tester, String text,
      {required String id}) async {
    events.add(PartyChannelReceived(
        partyPayload({'Type': 'Chat', 'Text': text}, id: id)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('chat: messaggi arrivati fuori dal player, puntino sul pulsante '
      'finché la chat non si apre (spec E §9.5)', (tester) async {
    await pumpPartyPlayer(tester);
    final channel = container.read(partyChannelProvider.notifier)
      // Come fuori dal player: nessun livello chat a schermo.
      ..detachChatLayer();
    await receiveChat(tester, 'mentre eri via', id: 'c1');
    channel.attachChatLayer();
    await tester.pump();
    expect(find.byKey(const Key('player-chat-unread')), findsOneWidget);
    await openChatWithEnter(tester);
    expect(find.byKey(const Key('player-chat-unread')), findsNothing);
    expect(container.read(partyChannelProvider).unread, 0);
    await finish(tester);
  });

  testWidgets('chat: i messaggi arrivati a chat aperta non diventano bolle '
      'alla chiusura', (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    await receiveChat(tester, 'eccomi', id: 'c1');
    expect(find.textContaining('eccomi'), findsOneWidget, reason: 'storico');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(chatField(), findsNothing);
    expect(find.byType(PartyChatBubble), findsNothing);
    expect(find.textContaining('eccomi'), findsNothing);
    await finish(tester);
  });

  testWidgets('chat aperta: la rotella sopra campo e storico non cambia il '
      'volume, altrove sì (spec E §9.3)', (tester) async {
    await pumpPartyPlayer(tester);
    await receiveChat(tester, 'primo', id: 'c1');
    await receiveChat(tester, 'secondo', id: 'c2');
    await openChatWithEnter(tester);
    final count = engine.volumes.length;
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    for (final target in [
      chatField(),
      find.byKey(const Key('party-chat-history')),
    ]) {
      await tester.sendEventToBinding(wheel.hover(tester.getCenter(target)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
      await tester.pump();
    }
    expect(engine.volumes, hasLength(count));
    expect(chatField(), findsOneWidget);
    // Sul film la rotella regola il volume, anche con la chat aperta.
    await tester.sendEventToBinding(wheel.hover(const Offset(720, 300)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pump();
    expect(engine.volumes, hasLength(count + 1));
    expect(chatField(), findsOneWidget);
    await finish(tester);
  });

  String? primaryFocus() => FocusManager.instance.primaryFocus?.debugLabel;

  /// Il nodo di focus del player, a cui arrivano i tasti.
  FocusNode playerFocus(WidgetTester tester) => tester
      .widget<Focus>(find.byWidgetPredicate((widget) =>
          widget is Focus && widget.focusNode?.debugLabel == 'player'))
      .focusNode!;

  testWidgets('chat aperta: Tab e Maiusc+Tab lasciano il focus al campo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(primaryFocus(), 'party-chat');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(primaryFocus(), 'party-chat');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.calls, isNot(contains('unpause')), reason: 'Spazio va al campo');
    expect(chatField(), findsOneWidget);
    await finish(tester);
  });

  testWidgets('chat aperta con il focus finito al player: il tasto dopo lo '
      'riporta al campo', (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    playerFocus(tester).requestFocus();
    await tester.pump();
    expect(primaryFocus(), 'player');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(primaryFocus(), 'party-chat');
    expect(api.calls, isNot(contains('unpause')));
    expect(chatField(), findsOneWidget);
    await finish(tester);
  });

  /// Apre il menu del distintivo del watch party (membri, "Esci").
  Future<void> openPartyMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    expect(find.text('Luigi'), findsOneWidget);
  }

  testWidgets(
      'chat che si chiude da sola sotto il menu del watch party: il focus '
      'resta al menu, Esc chiude solo il menu', (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    await openPartyMenu(tester);
    await tester.pump(PartyChatLayer.idleClose);
    expect(chatField(), findsNothing);
    expect(primaryFocus(), isNot(anyOf('player', 'party-chat')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Luigi'), findsNothing, reason: 'Esc chiude il menu');
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(api.calls, isNot(contains('leave')));
    // Chiuso il menu, i tasti tornano al player.
    expect(primaryFocus(), 'player');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.calls, contains('unpause'));
    await finish(tester);
  });

  testWidgets(
      'chat riaperta da un invio fallito sotto il menu del watch party: il '
      'focus resta al menu', (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    channelApi.sendGate = Completer<void>();
    channelApi.sendFailures.add(PartyChannelFailure.network);
    await tester.enterText(chatField(), 'ci siete?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    // Il clic sul film chiude la chat; poi si apre il menu.
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(chatField(), findsNothing);
    await openPartyMenu(tester);
    channelApi.sendGate!.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(chatField(), findsOneWidget, reason: 'la chat si riapre');
    expect(primaryFocus(), isNot(anyOf('player', 'party-chat')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Luigi'), findsNothing, reason: 'Esc chiude il menu');
    expect(chatField(), findsOneWidget, reason: 'la chat resta aperta');
    // Il primo tasto riporta il focus al campo.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(primaryFocus(), 'party-chat');
    await finish(tester);
  });

  testWidgets('errore con "Riprova" a fuoco: Invio riprova, non apre la chat',
      (tester) async {
    await pumpPartyPlayer(tester, failOpens: 2);
    expect(find.text(l.playerErrorTitle), findsOneWidget);
    Focus.of(tester.element(find.text(l.retry))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chatField(), findsNothing);
    expect(api.calls, contains('ignore-wait false'), reason: 'Riprova');
    await finish(tester);
  });

  testWidgets('Invio tenuto premuto: apre la chat, la ripetizione non la '
      'richiude', (tester) async {
    await pumpPartyPlayer(tester);
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ]) {
      await tester.sendKeyDownEvent(key);
      await tester.pump();
      await tester.pump();
      expect(chatField(), findsOneWidget);
      // Non gestita, la ripetizione andrebbe al campo (su Windows la passa
      // il motore) e, a campo vuoto, chiuderebbe la chat.
      expect(await tester.sendKeyRepeatEvent(key), isTrue);
      await tester.sendKeyUpEvent(key);
      await tester.pump();
      expect(chatField(), findsOneWidget);
      expect(primaryFocus(), 'party-chat');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
    }
    await finish(tester);
  });

  testWidgets('chat aperta: play/pausa della tastiera arriva al gruppo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await openChatWithEnter(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(api.calls.where((call) => call == 'unpause'), hasLength(1));
    expect(chatField(), findsOneWidget, reason: 'la chat resta aperta');
    expect(primaryFocus(), 'party-chat');
    // Con i tasti multimediali alla sessione media di sistema il player non
    // li esegue una seconda volta.
    mediaSession.handlesMediaKeys = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(api.calls.where((call) => call == 'unpause'), hasLength(1));
    await finish(tester);
  });

  /// I tasti sono di nuovo del player: Spazio arriva al gruppo.
  Future<void> expectPlayerKeys(WidgetTester tester) async {
    expect(primaryFocus(), 'player');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(api.calls, contains('unpause'));
  }

  group('chat chiusa: i tasti tornano al player (spec E §11)', () {
    testWidgets('clic sul film', (tester) async {
      await pumpPartyPlayer(tester);
      await openChatWithEnter(tester);
      await tester.tapAt(const Offset(700, 300));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pump();
      expect(chatField(), findsNothing);
      await expectPlayerKeys(tester);
      await finish(tester);
    });

    testWidgets('pannello "Audio e sottotitoli"', (tester) async {
      await pumpPartyPlayer(tester);
      await openChatWithEnter(tester);
      await tester.tap(find.byTooltip(l.playerAudioAndSubtitles));
      await tester.pumpAndSettle();
      expect(chatField(), findsNothing);
      expect(find.byType(TracksPanel), findsOneWidget);
      await expectPlayerKeys(tester);
      await finish(tester);
    });

    testWidgets('chiusura automatica', (tester) async {
      await pumpPartyPlayer(tester);
      await openChatWithEnter(tester);
      await tester.pump(PartyChatLayer.idleClose);
      await tester.pump();
      expect(chatField(), findsNothing);
      await expectPlayerKeys(tester);
      await finish(tester);
    });

    testWidgets('canale spento', (tester) async {
      await pumpPartyPlayer(tester);
      await openChatWithEnter(tester);
      // Il plugin è sparito: l'invio se ne accorge e il canale si spegne.
      channelApi.sendFailures.add(PartyChannelFailure.unavailable);
      await tester.enterText(chatField(), 'ci siete?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump();
      expect(container.read(partyChannelProvider).active, isFalse);
      expect(chatField(), findsNothing);
      await expectPlayerKeys(tester);
      await finish(tester);
    });

    testWidgets('tolti dal gruppo', (tester) async {
      await pumpPartyPlayer(tester);
      await openChatWithEnter(tester);
      emit(const GroupLeft('g1'));
      await tester.pump();
      await tester.pump();
      expect(chatField(), findsNothing);
      expect(primaryFocus(), 'player');
      // Fuori dal gruppo Spazio fa partire il video da solo.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(engine.calls, contains('play'));
      await finish(tester);
    });
  });

  Finder flying(String emoji) => find.descendant(
      of: find.byType(PartyReactionsLayer), matching: find.text(emoji));

  List<Map<String, dynamic>> sentReactions() => [
        for (final event in channelApi.sent)
          if (event is PartyOutgoingReaction) event.toJson(),
      ];

  testWidgets('reazioni: barretta dal pulsante, un clic manda e fa salire '
      '(spec E §10)', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('party-reaction-clap')));
    await tester.pump();
    await tester.pump();
    expect(sentReactions(), [
      {'Type': 'Reaction', 'Reaction': 'clap'},
    ]);
    expect(flying('👏'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PartyReactionsLayer), matching: find.text('Tu')),
        findsOneWidget);
    await finish(tester);
  });

  Map<String, dynamic> sentReaction(PartyReaction reaction) =>
      {'Type': 'Reaction', 'Reaction': reaction.id};

  testWidgets('reazioni: tasti 1–6 e tastierino', (tester) async {
    await pumpPartyPlayer(tester);
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump(PlayerScreen.reactionInterval);
    }
    expect(sentReactions(), [
      for (var round = 0; round < 2; round++)
        for (final reaction in PartyReaction.values) sentReaction(reaction),
    ]);
    await finish(tester);
  });

  testWidgets('reazioni: al massimo una ogni 200 ms', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(sentReactions(), [sentReaction(PartyReaction.joy)],
        reason: 'la seconda entro 200 ms si scarta');
    await tester.pump(PlayerScreen.reactionInterval);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad6);
    await tester.pump();
    expect(sentReactions(), [
      sentReaction(PartyReaction.joy),
      sentReaction(PartyReaction.facepalm),
    ]);
    await finish(tester);
  });

  testWidgets('reazioni: tenendo premuto il tasto la ripetizione non manda '
      'nulla', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    // Oltre il limite dei 200 ms: se la ripetizione contasse, passerebbe.
    await tester.pump(
        PlayerScreen.reactionInterval + const Duration(milliseconds: 50));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(sentReactions(), [sentReaction(PartyReaction.joy)]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    await finish(tester);
  });

  testWidgets('reazioni: con Ctrl, Alt o Meta i numeri non mandano nulla',
      (tester) async {
    await pumpPartyPlayer(tester);
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump(PlayerScreen.reactionInterval);
    }
    expect(sentReactions(), isEmpty);
    // Senza modificatori il tasto manda di nuovo la reazione.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(sentReactions(), [sentReaction(PartyReaction.joy)]);
    await finish(tester);
  });

  testWidgets('reazioni: con l\'orologio tornato indietro non restano '
      'bloccate', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    // L'orologio di sistema torna indietro di un'ora (per esempio una
    // sincronizzazione dell'ora).
    final past = clock.now().subtract(const Duration(hours: 1));
    await withClock(Clock.fixed(past),
        () => tester.sendKeyEvent(LogicalKeyboardKey.digit2));
    await tester.pump();
    expect(sentReactions(), [
      sentReaction(PartyReaction.joy),
      sentReaction(PartyReaction.scream),
    ]);
    await finish(tester);
  });

  testWidgets('reazioni: senza plugin i numeri non mandano nulla',
      (tester) async {
    await pumpPartyPlayer(tester, plugin: false);
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.numpad3,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump(PlayerScreen.reactionInterval);
    }
    expect(channelApi.sent, isEmpty);
    expect(find.byType(PartyReactionsLayer), findsNothing);
    expect(tester.takeException(), isNull);
    // I tasti del player funzionano come prima.
    await expectPlayerKeys(tester);
    await finish(tester);
  });

  testWidgets('reazioni: un clic sulla barretta e un tasto entro 200 ms ne '
      'mandano una sola', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('party-reaction-clap')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(sentReactions(), [sentReaction(PartyReaction.clap)]);
    await finish(tester);
  });

  testWidgets('reazioni: a chat aperta i numeri vanno al campo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(sentReactions(), isEmpty);
    await finish(tester);
  });

  testWidgets('reazioni degli altri: emoji e nome', (tester) async {
    await pumpPartyPlayer(tester);
    events.add(PartyChannelReceived(
        partyPayload({'Type': 'Reaction', 'Reaction': 'joy'}, id: 'r1')));
    await tester.pump();
    await tester.pump();
    expect(flying('😂'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PartyReactionsLayer),
            matching: find.text('Luigi')),
        findsOneWidget);
    await finish(tester);
  });

  /// La barretta delle reazioni è aperta (o sta entrando).
  Finder trayVisible() => find.byWidgetPredicate((widget) =>
      widget is AnimatedOpacity &&
      widget.opacity == 1 &&
      widget.child is AnimatedScale);

  testWidgets('barretta: Esc e clic sul film la chiudono; con la chat uno '
      'alla volta', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    expect(trayVisible(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(trayVisible(), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget,
        reason: 'Esc chiude solo la barretta');

    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(trayVisible(), findsNothing);
    expect(api.calls, isNot(contains('unpause')),
        reason: 'il clic chiude e basta');

    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(trayVisible(), findsNothing);
    expect(find.byKey(const Key('party-chat-field')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('barretta: senza il mouse sopra si chiude da sola',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    await tester.pump(
        PartyReactionsTray.idleClose - const Duration(milliseconds: 100));
    expect(trayVisible(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(trayVisible(), findsNothing);
    // Chiusa davvero: Esc non resta a lei.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(api.calls, contains('leave'));
    await finish(tester);
  });

  testWidgets('barretta aperta quando compare il post-play: si chiude, il '
      'primo Esc chiude il post-play', (tester) async {
    await pumpPartyPlayer(tester, segments: credits);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    expect(trayVisible(), findsOneWidget);
    await toCredits(tester);
    expect(trayVisible(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(l.playerWatchCredits), findsNothing,
        reason: 'il primo Esc chiude il post-play');
    expect(find.byType(PlayerScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('barretta aperta e riapertura non riuscita: si chiude, Esc '
      'esce dal player', (tester) async {
    // Il direct play non riesce: si guarda in transcodifica, dove cambiare
    // l'audio riapre il file.
    await pumpPartyPlayer(tester, failOpens: 1);
    final args = tester.widget<PlayerScreen>(find.byType(PlayerScreen)).args;
    // L'avviso della transcodifica coprirebbe il pulsante.
    ScaffoldMessenger.of(tester.element(find.byType(PlayerScreen)))
        .removeCurrentSnackBar();
    await tester.pump();
    await tester.tap(find.byTooltip(l.partyReactionsOpen));
    await tester.pump();
    expect(trayVisible(), findsOneWidget);
    engine.failOpens = 1;
    unawaited(
        container.read(playerControllerProvider(args).notifier).selectAudio(2));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text(l.playerErrorTitle), findsOneWidget);
    expect(trayVisible(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(api.calls, contains('leave'),
        reason: 'nessun riquadro aperto: Esc esce dal player');
    await finish(tester);
  });

  group('barretta aperta e reazioni non più disponibili: si chiude, Esc '
      'non resta a lei', () {
    testWidgets('canale spento', (tester) async {
      await pumpPartyPlayer(tester);
      await tester.tap(find.byTooltip(l.partyReactionsOpen));
      await tester.pump();
      // Il plugin è sparito: l'invio della reazione se ne accorge e il
      // canale si spegne.
      channelApi.sendFailures.add(PartyChannelFailure.unavailable);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      await tester.pump();
      expect(container.read(partyChannelProvider).active, isFalse);
      expect(find.byTooltip(l.partyReactionsOpen), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(api.calls, contains('leave'),
          reason: 'nessun riquadro aperto: Esc esce dal player');
      await finish(tester);
    });

    testWidgets('tolti dal gruppo', (tester) async {
      await pumpPartyPlayer(tester);
      await tester.tap(find.byTooltip(l.partyReactionsOpen));
      await tester.pump();
      emit(const GroupLeft('g1'));
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip(l.partyReactionsOpen), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing,
          reason: 'nessun riquadro aperto: Esc esce dal player');
      await finish(tester);
    });
  });

  testWidgets('menu del distintivo aperto: i controlli non si nascondono',
      (tester) async {
    await pumpPartyPlayer(tester);
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.unpause)));
    await tester.pump();
    await tester.pump();
    double opacity() => tester
        .widget<AnimatedOpacity>(
            find.byKey(const Key('player-controls-bottom')))
        .opacity;
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    await tester.pump(PlayerChromeController.hideDelay * 2);
    expect(opacity(), 1, reason: 'con il menu aperto i controlli restano');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(PlayerChromeController.hideDelay);
    expect(opacity(), 0, reason: 'chiuso il menu, si nascondono come sempre');
    await finish(tester);
  });

  testWidgets('precedente nel gruppo (spec H §9.1): pulsante, P, annuncio',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    expect(find.byTooltip(l.playerPreviousInQueue), findsNothing,
        reason: 'e4 è il primo della coda');
    expect(mediaSession.previousEnabled.last, isFalse);

    emit(PlayQueueUpdate('g1', queueWithPrevious()));
    await tester.pump();
    await tester.pump();
    expect(mediaSession.previousEnabled.last, isTrue);
    await tester.tap(find.byTooltip(l.playerPreviousInQueue));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('previous p1'));
    expect(announced(),
        contains(equals({'Type': 'Action', 'Action': 'PreviousItem'})));

    api.calls.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(api.calls, ['previous p1']);
    await finish(tester);
  });

  testWidgets('precedente con un plugin vecchio: niente annuncio',
      (tester) async {
    await pumpPartyPlayer(tester, queueFeature: false);
    emit(PlayQueueUpdate('g1', queueWithPrevious()));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip(l.playerPreviousInQueue));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('previous p1'));
    expect(announced(), isEmpty);
    await finish(tester);
  });

  testWidgets('gruppo chiuso dal server: il precedente torna quello da soli',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(PlayQueueUpdate('g1', queueWithPrevious()));
    await tester.pump();
    await tester.pump();
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip(l.playerPreviousInQueue), findsNothing);
    expect(mediaSession.previousEnabled.last, isFalse,
        reason: 'e4 non ha un episodio prima nella libreria finta');
    await finish(tester);
  });
}
