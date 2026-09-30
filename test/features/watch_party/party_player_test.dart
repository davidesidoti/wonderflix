import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
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
  late StreamController<ServerEvent> events;
  late FakeLibraryApi library;
  late ProviderContainer container;
  late GoRouter router;

  void emit(GroupUpdate update) => events.add(SyncPlayGroupUpdated(update));

  /// Home con il player del watch party aperto sopra: l'utente è già nel
  /// gruppo `g1` (Mario e Luigi), che guarda `e4` (`p1`).
  Future<void> pumpPartyPlayer(WidgetTester tester, {int failOpens = 0}) async {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    engine.failOpens = failOpens;
    engines = [];
    window = FakePlayerWindow();
    mediaSession = FakeMediaSession();
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    final playback = FakePlaybackApi();
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
    expect(find.text(l.watchPartyWaiting), findsNothing);
    await finish(tester);
  });

  testWidgets('nel watch party non c\'è l\'episodio successivo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.pump();
    expect(find.byTooltip(l.playerNextEpisode), findsNothing);
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

  testWidgets('prossimo episodio: il pulsante lo chiede al gruppo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.playerNextEpisode));
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
    expect(find.textContaining('Inizia tra'), findsNothing);
    await tester.tap(find.text(l.playerPlayNow));
    await tester.pump();
    expect(api.calls, contains('next p1'));
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
    expect(find.byTooltip(l.playerNextEpisode), findsOneWidget,
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
    expect(find.textContaining('Inizia tra'), findsOneWidget);

    engine.emitCompleted();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/play/e5');
    expect(router.state.uri.queryParameters, isNot(contains('party')));
    expect(api.calls, isNot(contains('next p1')));
    await finish(tester);
  });

  testWidgets('avvisi: pillola nel player, e le mie azioni in seconda persona',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyNoticePaused), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(l.watchPartyNoticePaused), findsNothing);

    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(find.text(l.watchPartyNoticeResumedByYou), findsOneWidget);
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
}
