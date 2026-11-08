import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/features/player/player_overlay.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/player_volume.dart';
import 'package:wonderflix/features/player/tracks_panel.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/form_factor.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeVideoEngine engine;
  late FakeLibraryApi library;
  late FakePlaybackApi playback;
  late List<String> authImageUrls;
  late GoRouter router;

  setUp(() {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
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
    playback = FakePlaybackApi();
  });

  /// Home ('/') con il player aperto sopra; [tv] come sul telecomando.
  Future<void> pumpPlayer(
    WidgetTester tester, {
    bool tv = true,
    bool settle = true,
    Size size = const Size(1440, 900),
  }) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/play/:id',
          builder: (context, state) => PlayerScreen(
            args: (
              itemId: state.pathParameters['id']!,
              start: playerStartFrom(state.uri),
              party: null,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize =
        size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryApiProvider.overrideWithValue(library),
          playbackApiProvider.overrideWithValue(playback),
          playbackServiceProvider.overrideWithValue(
            PlaybackService(
              api: playback,
              serverUrl: testServerUrl,
              authorization: () => 'MediaBrowser Token="t1"',
            ),
          ),
          videoEngineFactoryProvider.overrideWithValue(() => engine),
          playerWindowProvider.overrideWithValue(FakePlayerWindow()),
          mediaSessionProvider.overrideWithValue(FakeMediaSession()),
          playerSettingsProvider.overrideWith(
            () => FakePlayerSettings(const PlayerSettings()),
          ),
          playerVolumeProvider.overrideWith(() => FakePlayerVolume(100)),
          sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser)),
          ),
          appConfigProvider.overrideWithValue(testAppConfig),
          imageBuilderProvider.overrideWithValue(
            (image, fit) => const ColoredBox(color: Color(0xFF333333)),
          ),
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
          builder: (context, child) => FormFactorScope(tv: tv, child: child!),
        ),
      ),
    );
    unawaited(router.push('/play/e4'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  double controlsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('player-controls-bottom')))
      .opacity;

  /// In riproduzione i controlli spariscono dopo 3 s.
  Future<void> hideControls(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(controlsOpacity(tester), 0);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  void withNextEpisode() {
    final next = testItem(
      id: 'e5',
      name: 'Cat in the Bag',
      kind: ItemKind.episode,
      seriesName: 'Breaking Bad',
      seriesId: 's1',
      index: 5,
      seasonIndex: 1,
    );
    library.itemsById['e5'] = next;
    library.nextEpisodes['e4'] = next;
  }

  Finder primaryFocus() {
    final context = FocusManager.instance.primaryFocus!.context!;
    return find.byElementPredicate((e) => identical(e, context));
  }

  bool focusContains(Finder finder) =>
      find.descendant(of: primaryFocus(), matching: finder).evaluate().isNotEmpty;

  /// Il focus è al player (il suo nodo contiene tutto, controlli compresi).
  bool focusOnPlayer() => focusContains(find.byType(PlayerOverlay));

  /// Il focus è dentro "Riproduci ora".
  bool focusOnPlayNow() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<PlayNowButton>() !=
      null;

  /// Il nodo col focus contiene [finder] e non è il player.
  bool focusedOn(Finder finder) => focusContains(finder) && !focusOnPlayer();

  testWidgets('Giù: focus sulla fila dei pulsanti, Destra li scorre, Su torna '
      'alla barra', (tester) async {
    withNextEpisode();
    await pumpPlayer(tester);
    expect(controlsOpacity(tester), 1);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedOn(find.byType(PlayPauseIcon)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedOn(find.byIcon(LucideIcons.rewind)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedOn(find.byIcon(LucideIcons.fastForward)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedOn(find.byIcon(LucideIcons.captions)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedOn(find.byIcon(LucideIcons.skipForward)), isTrue);
    expect(engine.seeks, isEmpty, reason: 'le frecce spostano il focus');

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusOnPlayer(), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(engine.seeks.last, const Duration(seconds: 10));
    await unmount(tester);
  });

  testWidgets('OK sui pulsanti: pausa, −10 s', (tester) async {
    await pumpPlayer(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(engine.playing, isFalse);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(engine.seeks, [Duration.zero]);
    await unmount(tester);
  });

  testWidgets('senza episodio successivo la fila finisce su Audio e '
      'sottotitoli', (tester) async {
    await pumpPlayer(tester);
    expect(find.byTooltip('Episodio successivo'), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 4; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focusedOn(find.byIcon(LucideIcons.captions)), isTrue);
    await unmount(tester);
  });

  testWidgets('nascosti i controlli, il focus torna al player', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedOn(find.byType(PlayPauseIcon)), isTrue);

    await hideControls(tester);
    expect(focusOnPlayer(), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(engine.seeks.last, const Duration(seconds: 10));
    await unmount(tester);
  });

  testWidgets('Audio e sottotitoli: OK apre il pannello col focus sulla '
      "traccia scelta; OK su un'altra la sceglie", (tester) async {
    await pumpPlayer(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TracksPanel), findsOneWidget);
    expect(focusedOn(find.byIcon(LucideIcons.check)), isTrue);
    expect(focusedOn(find.text('English - AAC Stereo')), isFalse);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedOn(find.text('English - AAC Stereo')), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(engine.selectedAudio.last, '2');

    // Chiuso il pannello il focus torna sul suo pulsante.
    await back(tester);
    expect(find.byType(TracksPanel), findsNothing);
    expect(focusedOn(find.byIcon(LucideIcons.captions)), isTrue);
    await unmount(tester);
  });

  testWidgets('pannello: niente ritardo dei sottotitoli', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    expect(find.text('Dimensione'), findsOneWidget);
    expect(find.text('Ritardo sottotitoli'), findsNothing);
    await unmount(tester);
  });

  testWidgets('niente schermo intero, volume, guarda insieme', (tester) async {
    await pumpPlayer(tester, tv: false);
    // Fuori dalla TV ci sono: il controllo sotto non è a vuoto.
    expect(find.byTooltip('Schermo intero'), findsOneWidget);
    expect(find.byTooltip('Disattiva audio'), findsOneWidget);
    expect(find.byTooltip('Guarda insieme'), findsOneWidget);
    await unmount(tester);

    await pumpPlayer(tester);
    expect(find.byTooltip('Schermo intero'), findsNothing);
    expect(find.byTooltip('Disattiva audio'), findsNothing);
    expect(find.byKey(const Key('volume-slider')), findsNothing);
    expect(find.byTooltip('Guarda insieme'), findsNothing);
    await unmount(tester);
  });

  testWidgets('"Salta intro" prende il focus; OK salta', (tester) async {
    playback.segments = const [
      MediaSegment(
        type: MediaSegmentType.intro,
        start: Duration(seconds: 10),
        end: Duration(seconds: 90),
      ),
    ];
    await pumpPlayer(tester);
    await hideControls(tester);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(focusedOn(find.text('Salta intro')), isTrue);

    await press(tester, LogicalKeyboardKey.select);
    expect(engine.seeks.last, const Duration(seconds: 90));
    expect(engine.playing, isTrue, reason: 'OK salta, non mette in pausa');

    // Sparito il pulsante il focus torna al player.
    engine.emitPosition(const Duration(seconds: 90));
    await tester.pumpAndSettle();
    expect(find.text('Salta intro'), findsNothing);
    expect(focusOnPlayer(), isTrue);
    await unmount(tester);
  });

  testWidgets('"Salta intro" a fuoco: ←/→ saltano di 10 s, il focus resta', (
    tester,
  ) async {
    playback.segments = const [
      MediaSegment(
        type: MediaSegmentType.intro,
        start: Duration(seconds: 10),
        end: Duration(seconds: 90),
      ),
    ];
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(focusedOn(find.text('Salta intro')), isTrue);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(engine.seeks.last, const Duration(seconds: 30));
    expect(focusedOn(find.text('Salta intro')), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(engine.seeks.last, const Duration(seconds: 20));
    expect(focusedOn(find.text('Salta intro')), isTrue);
    await unmount(tester);
  });

  testWidgets('"Salta intro" sotto il pannello non prende il focus; chiuso il '
      'pannello sì', (tester) async {
    playback.segments = const [
      MediaSegment(
        type: MediaSegmentType.intro,
        start: Duration(seconds: 10),
        end: Duration(seconds: 90),
      ),
    ];
    await pumpPlayer(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    await press(tester, LogicalKeyboardKey.select);
    expect(focusedOn(find.byIcon(LucideIcons.check)), isTrue);

    engine.emitPosition(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(focusedOn(find.byIcon(LucideIcons.check)), isTrue);
    expect(find.text('Salta intro'), findsNothing);

    await back(tester);
    expect(find.byType(TracksPanel), findsNothing);
    expect(focusedOn(find.text('Salta intro')), isTrue);
    await unmount(tester);
  });

  testWidgets('scheda "Prossimo episodio" sotto il pannello: non compare', (
    tester,
  ) async {
    withNextEpisode();
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsNothing);
    expect(focusOnPlayNow(), isFalse);

    await back(tester);
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(focusOnPlayNow(), isTrue);
    await unmount(tester);
  });

  testWidgets('960×540: pannello, "Salta intro", scheda e post-play senza '
      'overflow e raggiungibili', (tester) async {
    const small = Size(960, 540);
    withNextEpisode();
    playback.segments = const [
      MediaSegment(
        type: MediaSegmentType.intro,
        start: Duration(seconds: 10),
        end: Duration(seconds: 90),
      ),
      MediaSegment(
        type: MediaSegmentType.outro,
        start: Duration(hours: 1, minutes: 55),
        end: Duration(hours: 2),
      ),
    ];
    await pumpPlayer(tester, size: small);
    // Fila completa.
    await press(tester, LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TracksPanel), findsOneWidget);
    // In fondo al pannello: le dimensioni dei sottotitoli.
    for (var i = 0; i < 12; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    // Le dimensioni vanno a capo: si arriva a "Molto grandi" con ←/→/↓.
    var reached = false;
    for (final key in [
      for (var i = 0; i < 4; i++) LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      for (var i = 0; i < 4; i++) LogicalKeyboardKey.arrowRight,
    ]) {
      reached = reached || focusedOn(find.text('Molto grandi'));
      await press(tester, key);
    }
    expect(reached || focusedOn(find.text('Molto grandi')), isTrue);
    await back(tester);

    engine.emitPosition(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(focusedOn(find.text('Salta intro')), isTrue);

    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Guarda i titoli'), findsOneWidget);
    expect(focusOnPlayNow(), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedOn(find.text('Guarda i titoli')), isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('scheda "Prossimo episodio": Riproduci ora ha il focus', (
    tester,
  ) async {
    withNextEpisode();
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 59, seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
    expect(focusOnPlayNow(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/play/e5');
    await unmount(tester);
  });

  testWidgets('post-play: Riproduci ora ha il focus', (tester) async {
    withNextEpisode();
    playback.segments = const [
      MediaSegment(
        type: MediaSegmentType.outro,
        start: Duration(hours: 1, minutes: 55),
        end: Duration(hours: 2),
      ),
    ];
    await pumpPlayer(tester);
    engine.emitPosition(const Duration(hours: 1, minutes: 55, seconds: 10));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Guarda i titoli'), findsOneWidget);
    expect(focusOnPlayNow(), isTrue);
    await unmount(tester);
  });
}
