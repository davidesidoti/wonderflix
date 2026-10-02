import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/media_session/media_session.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/pause_screen.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/player/player_chrome.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/features/player/player_loading.dart';
import 'package:wonderflix/features/player/player_overlay.dart';
import 'package:wonderflix/features/player/player_pill.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/player_volume.dart';
import 'package:wonderflix/features/player/post_play.dart';
import 'package:wonderflix/features/player/seek_bar.dart';
import 'package:wonderflix/features/player/tracks_panel.dart';
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

  /// Il router creato da [pumpPlayer]: la pagina in cima è lo stato attuale.
  late GoRouter router;
  var settings = const PlayerSettings();
  var savedVolume = 100.0;

  setUp(() {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    engines = [];
    playback = FakePlaybackApi();
    window = FakePlayerWindow();
    mediaSession = FakeMediaSession();
    settings = const PlayerSettings();
    savedVolume = 100;
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
  Future<void> pumpPlayer(WidgetTester tester, {bool settle = true}) async {
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
        playerVolumeProvider.overrideWith(() => FakePlayerVolume(savedVolume)),
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // Caricamento visibile: la linea gira, niente `pumpAndSettle`.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }
  }

  /// Smonta l'app e lascia scadere i timer (report di fine, attese).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  double controlsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('player-controls-bottom')))
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

  testWidgets('caricamento: sfondo e titolo finché arriva il primo fotogramma',
      (tester) async {
    engine.holdFirstFrame = true;
    await pumpPlayer(tester, settle: false);
    final layer = find.byKey(const Key('player-loading'));
    expect(layer, findsOneWidget);
    expect(find.descendant(of: layer, matching: find.text('BREAKING BAD')),
        findsOneWidget);
    expect(find.descendant(of: layer, matching: find.byTooltip('Indietro')),
        findsOneWidget);
    expect(controlsOpacity(tester), 0, reason: 'controlli nascosti');

    engine.completeFirstFrame();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(layer, findsNothing);
    expect(find.byType(LoadingLine), findsNothing);
    expect(controlsOpacity(tester), 1);
    await unmount(tester);
  });

  testWidgets('caricamento: senza primo fotogramma sfuma dopo 3 s',
      (tester) async {
    engine.holdFirstFrame = true;
    await pumpPlayer(tester, settle: false);
    // Prima dei 3 s il caricamento c'è ancora.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('player-loading')), findsOneWidget);
    // Margine: il conto parte da `ready`, raggiunto durante i primi pump.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-loading')), findsNothing);
    await unmount(tester);
  });

  testWidgets('controlli: il conto per nasconderli riparte dal primo fotogramma',
      (tester) async {
    engine.holdFirstFrame = true;
    await pumpPlayer(tester, settle: false);
    // Il video parte dopo 2,5 s (capita con le transcodifiche): il conto dei
    // 3 s, partito con `playing`, scadrebbe appena il caricamento sfuma.
    await tester.pump(const Duration(milliseconds: 2500));
    engine.completeFirstFrame();
    await tester.pump();
    // La linea del caricamento gira finché lo strato non esce dall'albero.
    await tester.pump(WfMotion.slow);
    await tester.pump(WfMotion.slow);
    expect(find.byKey(const Key('player-loading')), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(controlsOpacity(tester), 1,
        reason: 'il conto è ripartito dal primo fotogramma');
    await tester.pump(PlayerChromeController.hideDelay);
    await tester.pumpAndSettle();
    expect(controlsOpacity(tester), 0);
    await unmount(tester);
  });

  testWidgets('buffering: lo spinner solo oltre 300 ms', (tester) async {
    await pumpPlayer(tester);
    engine.emitBuffering(true);
    // Prima l'evento arriva al controller, poi la schermata si ricostruisce
    // (e parte l'attesa dello spinner).
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    engine.emitBuffering(false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
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

  testWidgets('tastiera: pillola con i riscontri; i salti si sommano',
      (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('+10 s · 00:10'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('+20 s · 00:20'), findsOneWidget);
    expect(engine.seeks,
        [const Duration(seconds: 10), const Duration(seconds: 20)]);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('In pausa'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Volume 95%'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(find.text('Audio disattivato'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(find.text('Sottotitoli +0,1 s'), findsOneWidget);

    await tester.pump(PlayerChromeController.feedbackDuration);
    await tester.pumpAndSettle();
    expect(find.text('Sottotitoli +0,1 s'), findsNothing);
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

  testWidgets('trascinando la barra i controlli restano', (tester) async {
    await pumpPlayer(tester);
    expect(controlsOpacity(tester), 1);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final bar = tester.getCenter(find.byType(SeekBar));
    await gesture.addPointer(location: bar);
    addTearDown(gesture.removePointer);
    await gesture.down(bar);
    // Col tasto premuto il mouse non "passa sopra": il conto per nascondere i
    // controlli riparte dai movimenti del trascinamento, per più di 3 s.
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(controlsOpacity(tester), 1);
    await gesture.up();

    // Finito il trascinamento, a mouse fermo il conto funziona come prima.
    await tester.pump(PlayerChromeController.hideDelay);
    expect(controlsOpacity(tester), 0);
    await unmount(tester);
  });

  testWidgets('i tasti non mostrano i controlli', (tester) async {
    await pumpPlayer(tester);
    await tester.pump(PlayerChromeController.hideDelay);
    await tester.pumpAndSettle();
    expect(controlsOpacity(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(engine.seeks.last, const Duration(seconds: 10));
    expect(controlsOpacity(tester), 0);
    await unmount(tester);
  });

  testWidgets('pausa: dopo 8 s senza mouse né tasti, "Stai guardando"',
      (tester) async {
    library.itemsById['e4'] = testItem(
      id: 'e4',
      name: 'Pilot',
      kind: ItemKind.episode,
      seriesName: 'Breaking Bad',
      seriesId: 's1',
      index: 4,
      seasonIndex: 1,
      overview: 'Un professore scopre di essere malato.',
    );
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(PlayerChromeController.pauseScreenDelay -
        const Duration(seconds: 1));
    expect(find.text('STAI GUARDANDO'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);
    expect(find.text('Un professore scopre di essere malato.'), findsOneWidget);
    expect(controlsOpacity(tester), 0);

    // Un tasto la chiude senza mostrare i controlli.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    expect(controlsOpacity(tester), 0);

    // Di nuovo dopo 8 s; il mouse la chiude e riporta i controlli.
    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(700, 400));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(720, 420));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    expect(controlsOpacity(tester), 1);
    await unmount(tester);
  });

  /// Mette in pausa con Spazio e aspetta che compaia "Stai guardando".
  Future<void> pauseUntilPauseScreen(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);
  }

  testWidgets('pausa: qualsiasi tasto la chiude, anche senza comando',
      (tester) async {
    await pumpPlayer(tester);
    await pauseUntilPauseScreen(tester);

    // La A non è un comando: chiude lo stesso la schermata e rifà gli 8 s.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);

    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('pausa: Esc la chiude soltanto, il secondo Esc esce',
      (tester) async {
    await pumpPlayer(tester);
    await pauseUntilPauseScreen(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    expect(find.text('home'), findsNothing, reason: 'si resta nel player');
    expect(playback.stopped, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(playback.stopped, hasLength(1));
    await unmount(tester);
  });

  testWidgets('pausa: con il pannello aperto non compare', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    await unmount(tester);
  });

  testWidgets('rotella: volume come le frecce, anche sulla barra del volume',
      (tester) async {
    savedVolume = 50;
    await pumpPlayer(tester);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(const Offset(720, 450)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(engine.volumes.last, 45);
    expect(find.text('Volume 45%'), findsOneWidget);

    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.pumpAndSettle();
    expect(engine.volumes.last, 55);
    expect(find.text('Volume 55%'), findsOneWidget);

    // Scorrimento orizzontale: niente.
    final count = engine.volumes.length;
    await tester.sendEventToBinding(wheel.scroll(const Offset(60, 0)));
    await tester.pumpAndSettle();
    expect(engine.volumes, hasLength(count));

    // Sopra la barra del volume.
    final slider = find.byKey(const Key('volume-slider'));
    await tester.sendEventToBinding(wheel.hover(tester.getCenter(slider)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.pumpAndSettle();
    expect(engine.volumes.last, 60);
    expect(tester.widget<Slider>(slider).value, 60);
    await unmount(tester);
  });

  testWidgets('rotella: i controlli non compaiono; chiude "Stai guardando"',
      (tester) async {
    await pumpPlayer(tester);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(const Offset(720, 450)));
    await tester.pump(PlayerChromeController.hideDelay);
    await tester.pumpAndSettle();
    expect(controlsOpacity(tester), 0);

    // Senza un nuovo movimento del mouse, come un tasto.
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(find.text('Volume 95%'), findsOneWidget);
    expect(controlsOpacity(tester), 0);

    await pauseUntilPauseScreen(tester);
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    expect(controlsOpacity(tester), 0);
    expect(engine.volumes.last, 90);
    await unmount(tester);
  });

  testWidgets('rotella sul pannello: il volume non cambia', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    final count = engine.volumes.length;
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(TracksPanel))));
    // Prima in su: la lista è in cima e non può scorrere, quindi lavora la
    // barriera del pannello; poi in giù.
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(engine.volumes, hasLength(count));
    expect(find.text('Volume 95%'), findsNothing);
    expect(find.text('Volume 100%'), findsNothing);
    await unmount(tester);
  });

  testWidgets('rotella: funziona anche durante il caricamento',
      (tester) async {
    engine.holdFirstFrame = true;
    await pumpPlayer(tester, settle: false);
    expect(find.byKey(const Key('player-loading')), findsOneWidget);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(const Offset(720, 450)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    // Niente `pumpAndSettle`: la linea del caricamento gira.
    await tester.pump();
    expect(engine.volumes.last, 95);
    expect(find.text('Volume 95%'), findsOneWidget);

    engine.completeFirstFrame();
    await tester.pump();
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle(); // il pannello esce scorrendo
    expect(find.text('English - AAC Stereo'), findsNothing);
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });

  testWidgets('pannello: dimensione dei sottotitoli subito e salvata; × chiude',
      (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grandi'));
    await tester.pump();
    expect(engine.subtitleScales.last, 1.25);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    expect(container.read(playerSettingsProvider).subtitleScale, 1.25);

    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.text('Grandi'), findsNothing);
    await unmount(tester);
  });

  testWidgets('pannello: un clic sul film lo chiude', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(300, 450));
    // Il film ha anche il doppio clic: il clic singolo vale dopo 300 ms.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('Dimensione'), findsNothing);
    expect(engine.playing, isTrue, reason: 'il clic chiude, non mette in pausa');
    await unmount(tester);
  });

  testWidgets('pannello: se la riapertura fallisce si chiude', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    expect(find.text('Dimensione'), findsOneWidget);

    // Un sottotitolo bruciato nel video fa rifare la conversione: la
    // riapertura non riesce e compare lo strato dell'errore.
    engine.failOpens = 1;
    await tester.tap(find.text('Italiano - PGS - Esterno'));
    await tester.pumpAndSettle();
    expect(find.text('Impossibile riprodurre il video'), findsOneWidget);
    expect(find.text('Dimensione'), findsNothing,
        reason: 'il pannello non resta a destra dello strato dell\'errore');
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

  testWidgets('chiusura della finestra: il volume si scrive subito',
      (tester) async {
    await pumpPlayer(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    final volume =
        container.read(playerVolumeProvider.notifier) as FakePlayerVolume;
    volume.holdFlush = Completer<void>();
    final closing = window.simulateClose();
    await tester.pump();
    expect(volume.flushes, 1);
    expect(window.destroyed, isFalse,
        reason: 'la finestra aspetta la scrittura');
    volume.holdFlush!.complete();
    await tester.pump();
    await closing;
    expect(window.destroyed, isTrue);
    await unmount(tester);
  });

  testWidgets(
      'chiusura della finestra: sparisce subito, prima che il video si spenga',
      (tester) async {
    savedVolume = 70;
    await pumpPlayer(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    final volume =
        container.read(playerVolumeProvider.notifier) as FakePlayerVolume;
    volume.holdFlush = Completer<void>();
    bool? engineDisposedAtHide;
    double? volumeAtHide;
    window.onHide = () {
      engineDisposedAtHide = engine.disposed;
      volumeAtHide = engine.volumes.lastOrNull;
    };
    final closing = window.simulateClose();
    await tester.pump();
    expect(engineDisposedAtHide, isFalse,
        reason: 'il motore si spegne solo a finestra già nascosta');
    expect(volumeAtHide, 0, reason: 'il film tace insieme alla finestra');
    expect(window.hidden, isTrue,
        reason: 'nascosta mentre il lavoro di uscita è ancora in corso');
    expect(window.destroyed, isFalse);
    volume.holdFlush!.complete();
    await tester.pump();
    await closing;
    expect(window.destroyed, isTrue);
    expect(container.read(playerVolumeProvider), 70,
        reason: 'il muto non diventa il volume salvato');
    expect(playback.stopped.single.volume, 70,
        reason: 'il server riceve il volume scelto, non lo zero del muto');
    expect(playback.stopped.single.isMuted, isFalse);
    await unmount(tester);
  });

  testWidgets(
      'chiusura della finestra: un errore nel lavoro di uscita chiude lo '
      'stesso', (tester) async {
    await pumpPlayer(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    final volume =
        container.read(playerVolumeProvider.notifier) as FakePlayerVolume;
    volume.holdFlush = Completer<void>();
    final closing = window.simulateClose();
    await tester.pump();
    expect(window.destroyed, isFalse);
    volume.holdFlush!.completeError(StateError('disco pieno'));
    await tester.pump();
    await closing;
    expect(window.destroyed, isTrue,
        reason: 'senza destroy il processo resterebbe vivo e invisibile');
    await unmount(tester);
  });

  testWidgets('chiusura della finestra: se non si nasconde chiude lo stesso',
      (tester) async {
    await pumpPlayer(tester);
    window.onHide = () => throw StateError('nascondi');
    final closing = window.simulateClose();
    await tester.pump();
    await closing;
    expect(window.destroyed, isTrue);
    expect(playback.stopped, hasLength(1));
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

  testWidgets('salto automatico: pillola "Intro saltata"', (tester) async {
    settings = const PlayerSettings(autoSkipIntro: true);
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
    await tester.pumpAndSettle();
    expect(engine.seeks.last, const Duration(seconds: 90));
    expect(find.text('Intro saltata'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('prossimo episodio: scheda e conto alla rovescia', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.text('Riproduci ora · 10'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget);
    expect(router.state.uri.path, '/play/e5');
    expect(router.state.extra, isA<PlayerReplacement>(),
        reason: 'la transizione parte dal nero, non dalla pagina sotto');
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

  testWidgets('strati dello stack: gli altri non si rimontano', (tester) async {
    withNextEpisode();
    engine.holdFirstFrame = true;
    // Il file è ancora in preparazione: gli strati condizionali non ci sono.
    playback.delay = const Duration(seconds: 1);
    await pumpPlayer(tester, settle: false);
    // Gli strati con stato: se uno strato condizionale ne sposta un altro
    // nello `Stack` senza chiavi, quello viene rimontato (elemento nuovo).
    final mounted = {
      for (final layer in [
        PlayerOverlay,
        PlayerLoadingLayer,
        PlayerPill,
        TracksPanelHost,
      ])
        layer: tester.element(find.byType(layer)),
    };
    // Il video: lo spinner del buffering gli compare accanto, sul film.
    final video = tester.element(find.byKey(const Key('fake-video')));
    void expectSameLayers() {
      mounted.forEach((layer, element) {
        expect(tester.element(find.byType(layer)), same(element),
            reason: '$layer rimontato');
      });
      expect(tester.element(find.byKey(const Key('fake-video'))), same(video),
          reason: 'video rimontato');
    }

    // Il file è pronto: compaiono "Stai guardando", "salta intro" e la
    // scheda del prossimo episodio...
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    mounted[PauseScreen] = tester.element(find.byType(PauseScreen));
    expectSameLayers();

    // ...il primo fotogramma fa comparire lo spinner, sopra la pillola...
    engine.completeFirstFrame();
    await tester.pump();
    await tester.pump(WfMotion.slow);
    await tester.pump(WfMotion.slow);
    expectSameLayers();

    // ...poi la scheda del prossimo episodio si mostra...
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expectSameLayers();

    // ...che poi sparisce.
    await tester.tap(find.text('Annulla'));
    await tester.pump();
    await tester.pump(WfMotion.fast); // la scheda sfuma via
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);
    expectSameLayers();
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
    expect(find.text('Riproduci ora · 10'), findsOneWidget);
    expect(find.text('S1:E5 · Cat in the Bag'), findsOneWidget,
        reason: 'solo nella scheda');
    expect(engines, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Riproduci ora · 7'), findsOneWidget);
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

  testWidgets('volume: l\'episodio successivo parte dall\'ultimo scelto',
      (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.volumes.last, 90);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumes.last, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(engines, hasLength(2));
    expect(engines.last.volumes.first, 90,
        reason: 'stesso volume, senza muto');
    await unmount(tester);
  });

  testWidgets('Annulla: a fine episodio si esce', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
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
    expect(find.textContaining('Riproduci ora ·'), findsNothing);

    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  /// Episodio con i titoli di coda noti (dall'1:55:00) e il successivo.
  void withCredits() {
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration(hours: 1, minutes: 55),
          end: Duration(hours: 2)),
    ];
    final next = testItem(
      id: 'e5',
      name: 'Cat in the Bag',
      kind: ItemKind.episode,
      seriesName: 'Breaking Bad',
      seriesId: 's1',
      index: 5,
      seasonIndex: 1,
      overview: 'Walter e Jesse devono liberarsi di un corpo.',
    );
    library.itemsById['e5'] = next;
    library.nextEpisodes['e4'] = next;
  }

  Future<void> toCredits(WidgetTester tester) async {
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  bool shrunk(WidgetTester tester) =>
      tester.widget<PostPlayFrame>(find.byType(PostPlayFrame)).active;

  testWidgets('post-play: sui titoli il film si rimpicciolisce, poi parte il '
      'successivo', (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    expect(shrunk(tester), isTrue);
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.text('Guarda i titoli'), findsOneWidget);
    expect(find.text('Riproduci ora · 10'), findsOneWidget);
    expect(controlsOpacity(tester), 0, reason: 'i controlli si nascondono');

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(engines, hasLength(2));
    expect(library.playedCalls, [('e4', true)]);
    await unmount(tester);
  });

  testWidgets('post-play: chiuso nell\'ultimo secondo del conto, il '
      'successivo non parte', (tester) async {
    withCredits();
    await pumpPlayer(tester);
    // Il post-play (e il suo conto) compare senza che passi tempo: da qui
    // si contano i 10 s.
    final start = tester.binding.clock.now();
    await toCredits(tester);
    await tester.pump(const Duration(milliseconds: 9900) -
        tester.binding.clock.now().difference(start));
    expect(find.text('Riproduci ora · 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    // Il pulsante che sfuma via (in `fast`) resta montato un attimo e il suo
    // conto scade: si va oltre i 10 s ma non oltre la dissolvenza.
    await tester.pump(const Duration(milliseconds: 120));
    expect(router.state.uri.path, '/play/e4',
        reason: 'il successivo non deve partire');
    expect(find.byType(PlayNowButton), findsOneWidget,
        reason: 'ancora montato mentre sfuma');
    expect(find.text('Riproduci ora'), findsOneWidget,
        reason: 'il conto è arrivato a zero');
    await tester.pumpAndSettle();
    expect(engines, hasLength(1));
    expect(router.state.uri.path, '/play/e4', reason: 'si resta nel player');
    expect(library.playedCalls, isEmpty);
    await unmount(tester);
  });

  testWidgets('post-play: "Guarda i titoli" torna a tutto schermo; a fine '
      'video si esce', (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    await tester.tap(find.text('Guarda i titoli'));
    await tester.pumpAndSettle();
    expect(shrunk(tester), isFalse);
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);
    expect(controlsOpacity(tester), 1);

    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('post-play: Esc lo chiude e si resta nel player',
      (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shrunk(tester), isFalse);
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });

  testWidgets('post-play: un clic sul film piccolo lo chiude', (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    await tester.tapAt(Offset(postPlayInset + 1440 * postPlayScale / 2,
        postPlayInset + 900 * postPlayScale / 2));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(shrunk(tester), isFalse);
    expect(engine.playing, isTrue, reason: 'il clic chiude, non mette in pausa');
    await unmount(tester);
  });

  testWidgets('post-play senza conto alla rovescia: a fine video si resta; '
      'Esc esce', (tester) async {
    settings = const PlayerSettings(autoplayNext: false);
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    expect(find.textContaining('Riproduci ora ·'), findsNothing);
    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsNothing);
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  /// Post-play senza conto alla rovescia, rimasto aperto a video finito.
  Future<void> toFinishedPostPlay(WidgetTester tester) async {
    settings = const PlayerSettings(autoplayNext: false);
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
  }

  testWidgets('post-play a video finito: "Guarda i titoli" esce',
      (tester) async {
    await toFinishedPostPlay(tester);
    await tester.tap(find.text('Guarda i titoli'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('post-play a video finito: un clic sul film piccolo esce',
      (tester) async {
    await toFinishedPostPlay(tester);
    await tester.tapAt(Offset(postPlayInset + 1440 * postPlayScale / 2,
        postPlayInset + 900 * postPlayScale / 2));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('post-play a video finito e a schermo intero: il primo Esc esce '
      'dallo schermo intero, il secondo dal player', (tester) async {
    settings = const PlayerSettings(autoplayNext: false);
    withCredits();
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    await toCredits(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(window.fullScreenCalls, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(window.fullScreenCalls, [true, false]);
    expect(shrunk(tester), isTrue, reason: 'il post-play resta');
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(router.state.uri.path, '/play/e4');
    expect(find.text('home'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('post-play: niente schermata di pausa; il pannello si chiude',
      (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    await toCredits(tester);
    expect(find.text('Dimensione'), findsNothing,
        reason: 'all\'inizio dei titoli il pannello si chiude');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    await unmount(tester);
  });

  testWidgets('scheda piccola: Esc vale "Annulla"', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(shrunk(tester), isFalse, reason: 'senza titoli noti il film resta');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });

  testWidgets('post-play a schermo intero: Esc lo chiude, lo schermo intero '
      'resta', (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(window.fullScreenCalls, [true]);
    await toCredits(tester);
    expect(shrunk(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shrunk(tester), isFalse);
    expect(window.fullScreenCalls, [true],
        reason: 'prima si chiude il post-play');
    expect(find.byTooltip('Esci da schermo intero'), findsOneWidget);
    expect(find.text('home'), findsNothing);
    await unmount(tester);
  });

  testWidgets('post-play: un clic fuori dal film piccolo non fa nulla',
      (tester) async {
    withCredits();
    await pumpPlayer(tester);
    await toCredits(tester);
    // Sotto l'immagine dell'episodio, a destra delle informazioni.
    await tester.tapAt(const Offset(1000, 700));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(shrunk(tester), isTrue);
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(engine.playing, isTrue, reason: 'nemmeno la pausa');
    await unmount(tester);
  });

  testWidgets('post-play: lo spinner del buffering sta sul film piccolo',
      (tester) async {
    withCredits();
    await pumpPlayer(tester);
    final video = tester.element(find.byKey(const Key('fake-video')));
    await toCredits(tester);
    engine.emitBuffering(true);
    await tester.pump();
    await tester.pump();
    await tester.pump(bufferingSpinnerDelay);
    await tester.pump(WfMotion.fast);
    // Lo spinner gira: niente `pumpAndSettle` finché si vede.
    final spinner = find.byType(CircularProgressIndicator);
    expect(spinner, findsOneWidget);
    const film = Rect.fromLTWH(postPlayInset, postPlayInset,
        1440 * postPlayScale, 900 * postPlayScale);
    expect(film.contains(tester.getCenter(spinner)), isTrue,
        reason: 'non sotto l\'immagine dell\'episodio');
    expect(tester.element(find.byKey(const Key('fake-video'))), same(video),
        reason: 'il video non si rimonta');

    engine.emitBuffering(false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(spinner, findsNothing);
    await unmount(tester);
  });

  testWidgets('post-play: aperto sui titoli, compare solo dopo il primo '
      'fotogramma', (tester) async {
    withCredits();
    engine.holdFirstFrame = true;
    await pumpPlayer(tester, settle: false);
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Il caricamento c'è ancora: la linea gira, niente `pumpAndSettle`.
    expect(find.byKey(const Key('player-loading')), findsOneWidget);
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);
    expect(find.byType(PlayNowButton), findsNothing,
        reason: 'nessun conto alla rovescia sotto il caricamento');
    expect(shrunk(tester), isFalse);

    engine.completeFirstFrame();
    await tester.pump();
    await tester.pump(WfMotion.slow);
    await tester.pump(WfMotion.slow);
    expect(find.byKey(const Key('player-loading')), findsNothing);
    await tester.pumpAndSettle();
    expect(shrunk(tester), isTrue);
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(find.textContaining('Riproduci ora ·'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('post-play: titoli noti arrivati a video fermo, compare senza '
      'aspettare la posizione', (tester) async {
    withCredits();
    final segments = Completer<void>();
    playback.segmentsGate = segments;
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump();
    expect(shrunk(tester), isFalse, reason: 'i titoli non sono ancora noti');

    segments.complete();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(shrunk(tester), isTrue);
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsNothing);
    await unmount(tester);
  });

  /// Opacità dello strato (`AnimatedSwitcher`) attorno a [finder].
  double slotOpacity(WidgetTester tester, Finder finder) => tester
      .widget<FadeTransition>(find
          .ancestor(of: finder, matching: find.byType(FadeTransition))
          .first)
      .opacity
      .value;

  testWidgets('scheda: lo strato non la sfuma, entra con la sua animazione',
      (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(slotOpacity(tester, find.text('PROSSIMO EPISODIO')), 1);
    await unmount(tester);
  });

  testWidgets('post-play: lo strato non lo sfuma, entra con la sua animazione',
      (tester) async {
    withCredits();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(slotOpacity(tester, find.text('PROSSIMO EPISODIO')), 1);
    await unmount(tester);
  });

  testWidgets('scheda piccola: compare quando arriva la durata, a video fermo',
      (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(minutes: 59, seconds: 40));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);

    // La durata vera è un'ora: si è già negli ultimi 30 s.
    engine.emitDuration(const Duration(hours: 1));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
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

  testWidgets('anteprime di un\'altra sorgente: URL con quella sorgente',
      (tester) async {
    library.itemsById['e4'] = JellyfinItem.fromJson({
      'Id': 'e4',
      'Name': 'Pilot',
      'Type': 'Episode',
      'Trickplay': {
        'ms2': {
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
        'https://media.example.com/Videos/e4/Trickplay/320/3.jpg?mediaSourceId=ms2');
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

  testWidgets('pannello media: play e pausa mostrano la pillola come Spazio',
      (tester) async {
    await pumpPlayer(tester);
    expect(find.text('In pausa'), findsNothing);

    mediaSession.press(MediaButton.pause);
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isFalse);
    expect(find.text('In pausa'), findsOneWidget);

    mediaSession.press(MediaButton.play);
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isTrue);
    expect(find.text('Riproduzione'), findsOneWidget);
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
    expect(mediaSession.nextEnabled.last, isFalse,
        reason: 'e5 è l\'ultimo: niente "successivo"');

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

  testWidgets('segnala il player aperto finché non si esce', (tester) async {
    await pumpPlayer(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    expect(container.read(playerActiveProvider), isTrue);

    mediaSession.press(MediaButton.stop);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(container.read(playerActiveProvider), isFalse);
    await unmount(tester);
  });
}
