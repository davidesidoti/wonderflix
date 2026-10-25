import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_chrome.dart';
import 'package:wonderflix/features/player/player_pill.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/player_volume.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeVideoEngine engine;
  late FakePlayerWindow window;

  setUp(() {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    window = FakePlayerWindow();
  });

  /// Il player aperto sopra la Home, col dito ([touch]) o col mouse.
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required bool touch,
    Size surfaceSize = const Size(844, 390),
  }) async {
    final playback = FakePlaybackApi();
    final library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(
        id: 'e4',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 4,
        seasonIndex: 1,
      );
    final router = GoRouter(
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
    await pumpAppRouter(
      tester,
      router,
      surfaceSize: surfaceSize,
      touch: touch,
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
        playerWindowProvider.overrideWithValue(window),
        mediaSessionProvider.overrideWithValue(FakeMediaSession()),
        playerSettingsProvider.overrideWith(
          () => FakePlayerSettings(const PlayerSettings()),
        ),
        playerVolumeProvider.overrideWith(() => FakePlayerVolume(100)),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
        authImageProvider.overrideWithValue(
          (url) => MemoryImage(Uint8List.fromList(transparentPng)),
        ),
      ],
    );
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();
  }

  /// Smonta l'app e lascia scadere i timer (report di fine, attese).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  double controlsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('player-controls-bottom')))
      .opacity;

  /// Il tocco singolo vale dopo l'attesa del doppio tocco.
  Future<void> settleTap(WidgetTester tester) async {
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  Future<void> doubleTapAt(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  Future<void> hideControls(WidgetTester tester) async {
    await tester.pump(PlayerChromeController.hideDelay);
    await tester.pumpAndSettle();
    expect(controlsOpacity(tester), 0);
  }

  const center = Offset(422, 195);

  testWidgets('tocco: un tocco sul video mostra i controlli e non mette in '
      'pausa', (tester) async {
    await pumpPlayer(tester, touch: true);
    expect(engine.playing, isTrue);
    await hideControls(tester);

    await tester.tapAt(center);
    await settleTap(tester);
    expect(controlsOpacity(tester), 1);
    expect(engine.playing, isTrue);
    await unmount(tester);
  });

  testWidgets('tocco: un tocco con i controlli visibili li nasconde', (
    tester,
  ) async {
    await pumpPlayer(tester, touch: true);
    expect(controlsOpacity(tester), 1);

    await tester.tapAt(center);
    await settleTap(tester);
    expect(controlsOpacity(tester), 0);
    expect(engine.playing, isTrue);
    await unmount(tester);
  });

  testWidgets('tocco: un dito che trema di poco non riaccende e spegne i '
      'controlli', (tester) async {
    await pumpPlayer(tester, touch: true);
    await hideControls(tester);

    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(2, 1));
    await gesture.up();
    await settleTap(tester);
    expect(controlsOpacity(tester), 1);
    await unmount(tester);
  });

  testWidgets('tocco: doppio tocco sulla metà destra va avanti di 10 s, '
      'sulla sinistra indietro di 10 s', (tester) async {
    await pumpPlayer(tester, touch: true);
    engine.emitPosition(const Duration(minutes: 1));
    await tester.pump();

    await doubleTapAt(tester, const Offset(700, 195));
    expect(engine.position, const Duration(seconds: 70));
    expect(find.byType(PlayerPill), findsOneWidget, reason: 'la pillola');
    expect(window.fullScreenCalls, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    await doubleTapAt(tester, const Offset(140, 195));
    expect(engine.position, const Duration(seconds: 60));
    expect(engine.playing, isTrue);
    await unmount(tester);
  });

  testWidgets('tocco: niente cursore del volume', (tester) async {
    await pumpPlayer(tester, touch: true);
    expect(find.byKey(const Key('volume-slider')), findsNothing);
    expect(find.byTooltip('Disattiva audio'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('mouse: tap = play/pausa, doppio clic = schermo intero', (
    tester,
  ) async {
    await pumpPlayer(tester, touch: false, surfaceSize: const Size(1440, 900));
    expect(find.byKey(const Key('volume-slider')), findsOneWidget);

    await tester.tapAt(const Offset(720, 450));
    await settleTap(tester);
    expect(engine.playing, isFalse);

    await doubleTapAt(tester, const Offset(1200, 450));
    expect(window.fullScreenCalls, [true]);
    await unmount(tester);
  });
}
