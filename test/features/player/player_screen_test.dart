import 'dart:async';

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
import 'package:wonderflix/core/media_session/media_session.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/seek_bar.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  /// Motore della prima schermata; ogni episodio successivo ne ha uno nuovo.
  late FakeVideoEngine engine;

  /// Motori creati, uno per schermata del player, in ordine.
  late List<FakeVideoEngine> engines;
  late FakePlaybackApi playback;
  late FakePlayerWindow window;
  late FakeLibraryApi library;
  late FakeMediaSession mediaSession;
  late List<String> authImageUrls;
  var settings = const PlayerSettings();

  setUp(() {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    engines = [];
    playback = FakePlaybackApi();
    window = FakePlayerWindow();
    mediaSession = FakeMediaSession();
    settings = const PlayerSettings();
    library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(
        id: 'e4',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 4,
        seasonIndex: 1,
      );
    authImageUrls = [];
  });

  /// Home ('/') con il player aperto sopra, come nell'app.
  Future<void> pumpPlayer(WidgetTester tester) async {
    final router = GoRouter(routes: [
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
          ),
          fullscreen: state.uri.queryParameters['fs'] == '1',
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
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
        playerSettingsProvider.overrideWith(() => FakePlayerSettings(settings)),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        appConfigProvider.overrideWithValue(testAppConfig),
        imageBuilderProvider
            .overrideWithValue((image, fit) => const ColoredBox(color: Color(0xFF333333))),
        authImageProvider.overrideWithValue((url) {
          authImageUrls.add(url);
          return MemoryImage(Uint8List.fromList(transparentPng));
        }),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();
  }

  /// Smonta l'app e lascia scadere i timer (report di fine, attese).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  double controlsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('player-controls')))
      .opacity;

  testWidgets('video, titolo, episodio e controlli', (tester) async {
    await pumpPlayer(tester);
    expect(find.byKey(const Key('fake-video')), findsOneWidget);
    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('S1:E4 · Pilot'), findsOneWidget);
    expect(find.byTooltip('Pausa'), findsOneWidget);
    expect(window.preventCloseCalls, [true]);
    await unmount(tester);
  });

  testWidgets('tastiera: pausa, salto, volume, muto, ritardo', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.seeks.last, const Duration(seconds: 10));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.volumes.last, 95);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumes.last, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(engine.subtitleDelays.last, const Duration(milliseconds: 100));
    await unmount(tester);
  });

  testWidgets('F e Esc: schermo intero, poi finestra, poi uscita',
      (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(window.fullScreenCalls, [true]);
    expect(find.byTooltip('Esci da schermo intero'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(window.fullScreenCalls, [true, false]);
    expect(find.text('home'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(playback.stopped, hasLength(1));
    expect(window.preventCloseCalls, [true, false]);
    await unmount(tester);
  });

  testWidgets('controlli nascosti dopo 3 s, di nuovo visibili col mouse',
      (tester) async {
    await pumpPlayer(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(controlsOpacity(tester), 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(700, 400));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(720, 420));
    await tester.pump();
    expect(controlsOpacity(tester), 1);

    // In pausa i controlli restano visibili.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(seconds: 5));
    expect(controlsOpacity(tester), 1);
    await unmount(tester);
  });

  testWidgets('pannello audio e sottotitoli; Esc lo chiude', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    expect(find.text('English - AAC Stereo'), findsOneWidget);

    await tester.tap(find.text('English - AAC Stereo'));
    await tester.pump();
    expect(engine.selectedAudio.last, '2');

    await tester.tap(find.text('Nessuno'));
    await tester.pump();
    expect(engine.selectedSubtitle.last, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('English - AAC Stereo'), findsNothing);
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });

  testWidgets('avviso di conversione: non resta sulla Home all\'uscita',
      (tester) async {
    engine.failOpens = 1;
    await pumpPlayer(tester);
    expect(find.text('Il server sta convertendo questo video.'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Il server sta convertendo questo video.'), findsNothing);
    await unmount(tester);
  });

  testWidgets('errore: Riprova riavvia', (tester) async {
    engine.failOpens = 2;
    await pumpPlayer(tester);
    expect(find.text('Impossibile riprodurre il video'), findsOneWidget);
    expect(find.text('Il video non si è avviato.'), findsOneWidget);

    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pausa'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('errore: Torna indietro esce dal player', (tester) async {
    engine.failOpens = 2;
    await pumpPlayer(tester);
    await tester.tap(find.text('Torna indietro'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('chiusura della finestra: fine della sessione, poi chiusura',
      (tester) async {
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(minutes: 5));
    final closing = window.simulateClose();
    await tester.pump();
    await closing;
    expect(playback.stopped.single.position, const Duration(minutes: 5));
    expect(window.destroyed, isTrue);
    await unmount(tester);
  });

  JellyfinItem episode5() => testItem(
        id: 'e5',
        name: 'Cat in the Bag',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 5,
        seasonIndex: 1,
      );

  void withNextEpisode() {
    final next = episode5();
    library.itemsById['e5'] = next;
    library.nextEpisodes['e4'] = next;
  }

  testWidgets('salta intro: pulsante durante l\'intro', (tester) async {
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Salta intro'));
    await tester.pump();
    expect(engine.seeks.last, const Duration(seconds: 90));
    await unmount(tester);
  });

  testWidgets('prossimo episodio: scheda e conto alla rovescia', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.text('Inizia tra 10 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    expect(playback.stopped.first.itemId, 'e4');
    expect(engines, hasLength(2), reason: 'un motore per episodio');
    expect(engine.disposed, isTrue);
    expect(engines.last.disposed, isFalse);
    expect(library.playedCalls, [('e4', true)],
        reason: 'nei titoli di coda: episodio visto');
    // La nuova schermata blocca la chiusura prima che la vecchia la
    // rilasci: le richieste si contano, quindi resta bloccata.
    expect(window.preventCloseCalls, [true, true, false]);
    await unmount(tester);
  });

  testWidgets('conto alla rovescia fermo in pausa', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Inizia tra 10 s'), findsOneWidget);
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget,
        reason: 'solo nella scheda');
    expect(engines, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Inizia tra 7 s'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('episodio successivo già iniziato: riprende da dove era',
      (tester) async {
    final next = testItem(
      id: 'e5',
      name: 'Cat in the Bag',
      kind: ItemKind.episode,
      seriesName: 'Breaking Bad',
      seriesId: 's1',
      index: 5,
      seasonIndex: 1,
      positionTicks: durationToTicks(const Duration(minutes: 12)),
      playedPercentage: 25,
    );
    library.itemsById['e5'] = next;
    library.nextEpisodes['e4'] = next;
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(engines, hasLength(2));
    expect(engines.last.opened.single.start, const Duration(minutes: 12));
    expect(library.playedCalls, isEmpty,
        reason: 'lasciato a metà: resta in corso');
    await unmount(tester);
  });

  testWidgets('Annulla: a fine episodio si esce', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Annulla'));
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);

    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('fine episodio: parte il successivo', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('riproduzione automatica spenta: niente conto alla rovescia',
      (tester) async {
    settings = const PlayerSettings(autoplayNext: false);
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.textContaining('Inizia tra'), findsNothing);

    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('N a schermo intero: il successivo resta a schermo intero',
      (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    expect(window.fullScreenCalls, [true], reason: 'mai uscito');
    expect(find.byTooltip('Esci da schermo intero'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('anteprima trickplay sulla barra', (tester) async {
    library.itemsById['e4'] = JellyfinItem.fromJson({
      'Id': 'e4',
      'Name': 'Pilot',
      'Type': 'Episode',
      'Trickplay': {
        'ms1': {
          '320': {
            'Width': 320,
            'Height': 180,
            'TileWidth': 10,
            'TileHeight': 10,
            'ThumbnailCount': 700,
            'Interval': 10000,
          },
        },
      },
    });
    await pumpPlayer(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SeekBar)));
    await tester.pump();
    expect(authImageUrls.last,
        'https://media.example.com/Videos/e4/Trickplay/320/3.jpg?mediaSourceId=ms1');
    await unmount(tester);
  });

  testWidgets('pannello media: titolo, stato, tasti e chiusura',
      (tester) async {
    await pumpPlayer(tester);
    expect(mediaSession.metadata.last.title, 'Breaking Bad');
    expect(mediaSession.metadata.last.subtitle, 'S1:E4 · Pilot');
    expect(mediaSession.metadata.last.thumbnailUrl, isNotNull);
    expect(mediaSession.playingStates.last, isTrue);

    await tester.pump(const Duration(seconds: 5));
    expect(mediaSession.timelines, isNotEmpty);

    mediaSession.press(MediaButton.pause);
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isFalse);

    mediaSession.press(MediaButton.play);
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isTrue);

    mediaSession.press(MediaButton.stop);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(mediaSession.cleared, 1, reason: 'uscendo il pannello sparisce');
    expect(mediaSession.disposed, isFalse, reason: 'la sessione è dell\'app');
    await unmount(tester);
  });

  testWidgets('pannello media: pausa e play non invertono uno stato vecchio',
      (tester) async {
    await pumpPlayer(tester);
    mediaSession.press(MediaButton.play);
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isTrue, reason: 'già in riproduzione');

    mediaSession
      ..press(MediaButton.pause)
      ..press(MediaButton.pause);
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isFalse);
    await unmount(tester);
  });

  testWidgets('tasti multimediali: ignorati se li gestisce la sessione',
      (tester) async {
    mediaSession.handlesMediaKeys = true;
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(engine.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaStop);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });

  testWidgets('pannello media: "successivo" solo se c\'è un episodio dopo',
      (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    expect(mediaSession.nextEnabled.last, isTrue);
    mediaSession.press(MediaButton.next);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    expect(mediaSession.cleared, 0,
        reason: 'passando all\'episodio successivo il pannello resta');
    expect(mediaSession.metadata.last.subtitle, 'S1:E5 · Cat in the Bag');

    // Il pannello comanda il nuovo episodio.
    mediaSession.press(MediaButton.pause);
    await tester.pump();
    await tester.pump();
    expect(engines.last.playing, isFalse);

    mediaSession.press(MediaButton.stop);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(mediaSession.cleared, 1);
    await unmount(tester);
  });
}
