import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_chrome.dart';
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
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize =
        const Size(1440, 900) * tester.view.devicePixelRatio;
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

  testWidgets('OK: pausa e controlli; di nuovo OK riprende', (tester) async {
    await pumpPlayer(tester);
    expect(engine.playing, isTrue);
    await hideControls(tester);

    await press(tester, LogicalKeyboardKey.select);
    expect(engine.playing, isFalse);
    expect(controlsOpacity(tester), 1);

    await press(tester, LogicalKeyboardKey.select);
    expect(engine.playing, isTrue);
    await unmount(tester);
  });

  testWidgets('Destra/Sinistra: ±10 s e controlli visibili', (tester) async {
    await pumpPlayer(tester);
    await hideControls(tester);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(engine.seeks.last, const Duration(seconds: 10));
    expect(controlsOpacity(tester), 1);

    engine.emitPosition(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 2));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(engine.seeks.last, const Duration(seconds: 20));
    await unmount(tester);
  });

  testWidgets('Destra con il trickplay: anteprima sulla barra', (tester) async {
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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      authImageUrls.last,
      'https://media.example.com/Videos/e4/Trickplay/320/0.jpg?mediaSourceId=ms1',
    );
    await unmount(tester);
  });

  testWidgets('Su/Giù: niente volume, controlli visibili', (tester) async {
    await pumpPlayer(tester);
    await hideControls(tester);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(controlsOpacity(tester), 1);
    await hideControls(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(controlsOpacity(tester), 1);
    expect(engine.volumes.where((v) => v != 100), isEmpty);
    await unmount(tester);
  });

  testWidgets('tasti media: avanti, indietro, play/pausa', (tester) async {
    await pumpPlayer(tester);
    await press(tester, LogicalKeyboardKey.mediaFastForward);
    expect(engine.seeks.last, const Duration(seconds: 10));
    engine.emitPosition(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 2));
    await press(tester, LogicalKeyboardKey.mediaRewind);
    expect(engine.seeks.last, const Duration(seconds: 20));

    await press(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(engine.playing, isFalse);
    await press(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(engine.playing, isTrue);
    await unmount(tester);
  });

  testWidgets('Indietro: pannello, poi controlli, poi esce', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.pumpAndSettle();
    expect(find.byType(TracksPanel), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TracksPanel), findsNothing);
    expect(controlsOpacity(tester), 1);
    expect(router.state.uri.path, '/play/e4');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controlsOpacity(tester), 0);
    expect(router.state.uri.path, '/play/e4');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(engine.disposed, isTrue);
    expect(router.state.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Indietro con "Stai guardando": la chiude, poi esce', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await press(tester, LogicalKeyboardKey.select);
    await tester.pump(PlayerChromeController.pauseScreenDelay);
    await tester.pumpAndSettle();
    expect(find.text('STAI GUARDANDO'), findsOneWidget);

    // Su Android il Back arriva prima come tasto, poi come pop di sistema.
    await tester.sendKeyEvent(LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('STAI GUARDANDO'), findsNothing);
    expect(router.state.uri.path, '/play/e4');

    await tester.sendKeyEvent(LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await back(tester);
    expect(router.state.uri.path, '/');
    await unmount(tester);
  });

  testWidgets('Indietro durante il caricamento esce subito', (tester) async {
    playback.delay = const Duration(seconds: 1);
    await pumpPlayer(tester, settle: false);
    await back(tester);
    expect(router.state.uri.path, '/');
    await unmount(tester);
  });

  testWidgets("Indietro sull'errore esce subito", (tester) async {
    engine.failOpens = 2;
    await pumpPlayer(tester);
    expect(find.text('Impossibile riprodurre il video'), findsOneWidget);
    await back(tester);
    expect(router.state.uri.path, '/');
    await unmount(tester);
  });

  testWidgets('fuori dalla TV Su/Giù cambiano il volume', (tester) async {
    await pumpPlayer(tester, tv: false);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(engine.volumes.last, 95);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(engine.volumes.last, 100);
    await unmount(tester);
  });
}
