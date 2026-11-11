import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/trailers/trailers_api.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/player/player_commands.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_volume.dart';
import 'package:wonderflix/features/trailer/trailer_screen.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/trailer_fakes.dart';

void main() {
  late FakeTrailersApi api;
  late FakeVideoEngine engine;
  late GoRouter router;

  setUp(() {
    api = FakeTrailersApi();
    engine = FakeVideoEngine();
  });

  Future<void> pumpTrailer(
    WidgetTester tester, {
    bool tv = false,
    bool touch = false,
    double volume = 100,
  }) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/trailer',
          builder: (context, state) => const TrailerScreen(
            subject: LibraryTrailer('m1'),
            title: 'Dune',
            backdropItemId: 'm1',
          ),
        ),
      ],
    );
    await pumpAppRouter(
      tester,
      router,
      tv: tv,
      touch: touch,
      overrides: [
        trailersApiProvider.overrideWithValue(api),
        videoEngineFactoryProvider.overrideWithValue(() => engine),
        clientInfoProvider.overrideWithValue(testClientInfo),
        playerVolumeProvider.overrideWith(() => FakePlayerVolume(volume)),
      ],
    );
    unawaited(router.push('/trailer'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  test('trailerRoute', () {
    expect(trailerRoute(const LibraryTrailer('a1')), '/trailer/item/a1');
    expect(
      trailerRoute(
        const TmdbTrailer('tv', 7),
        title: 'Dark',
        backdropItemId: 's1',
      ),
      '/trailer/tmdb/tv/7?title=Dark&backdrop=s1',
    );
  });

  testWidgets('preparingThenPlays', (tester) async {
    api.startResult = const TrailerStatus('k1', TrailerState.downloading);
    api.statuses = const [
      TrailerStatus('k1', TrailerState.downloading),
      TrailerStatus('k1', TrailerState.ready),
    ];
    await pumpTrailer(tester);
    expect(find.text('Preparo il trailer…'), findsOneWidget);
    expect(engine.opened, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(api.statusCalls, 2);
    expect(engine.opened.single.url, 'https://media.example.com/k1/Stream');
    expect(engine.opened.single.headers['Authorization'], isNotNull);
    expect(engine.calls, ['open', 'play']);
    expect(find.text('Preparo il trailer…'), findsNothing);
  });

  testWidgets('failedShowsUnavailable', (tester) async {
    api.startResult = const TrailerStatus('k1', TrailerState.failed);
    await pumpTrailer(tester);
    expect(find.text('Trailer non disponibile'), findsOneWidget);
    expect(find.text('Chiudi'), findsOneWidget);
    expect(engine.opened, isEmpty);

    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('noneShowsUnavailable', (tester) async {
    api.startResult = const TrailerStatus('k1', TrailerState.none);
    await pumpTrailer(tester);
    expect(find.text('Trailer non disponibile'), findsOneWidget);
    expect(engine.opened, isEmpty);
  });

  testWidgets('givesUpAfterThreeMinutes', (tester) async {
    api.startResult = const TrailerStatus('k1', TrailerState.downloading);
    api.statuses = const [TrailerStatus('k1', TrailerState.downloading)];
    await pumpTrailer(tester);
    for (var i = 0; i < 181; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Trailer non disponibile'), findsOneWidget);
    final calls = api.statusCalls;
    await tester.pump(const Duration(seconds: 5));
    expect(api.statusCalls, calls);
  });

  testWidgets('closingWhilePreparingStopsPolling', (tester) async {
    api.startResult = const TrailerStatus('k1', TrailerState.downloading);
    api.statuses = const [TrailerStatus('k1', TrailerState.downloading)];
    await pumpTrailer(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(api.statusCalls, 1);

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('home'), findsOneWidget);
    expect(api.statusCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closesAtTheEnd', (tester) async {
    await pumpTrailer(tester);
    expect(engine.calls, ['open', 'play']);
    engine.emitCompleted();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(engine.disposed, isTrue);
  });

  testWidgets('tvKeys', (tester) async {
    await pumpTrailer(tester, tv: true);
    expect(engine.playing, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(engine.calls.last, 'pause');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(engine.calls.last, 'play');

    engine.emitPosition(const Duration(seconds: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.seeks.last, const Duration(seconds: 40));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(engine.seeks.last, const Duration(seconds: 30));
    engine.emitPosition(const Duration(seconds: 4));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(engine.seeks.last, Duration.zero);

    // Su Android il Back arriva prima come tasto, poi come pop di sistema.
    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pump();
    expect(router.state.uri.path, '/trailer');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('playBlockedShowsAPlayButton', (tester) async {
    engine.blockNextPlay();
    await pumpTrailer(tester);
    expect(engine.playing, isFalse);
    final button = find.byKey(const ValueKey('trailer-tap-to-play'));
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(engine.calls.last, 'play');
    expect(engine.playing, isTrue);
    expect(button, findsNothing);
  });

  testWidgets('startsAtTheSavedVolume', (tester) async {
    final order = _OrderedEngine();
    engine = order;
    await pumpTrailer(tester, volume: 40);
    expect(engine.volumes, [40]);
    expect(order.volumesAtPlay, 1, reason: 'applicato prima di play()');
  });

  testWidgets('sliderChangesTheVolume', (tester) async {
    await pumpTrailer(tester);
    final slider = find.byKey(const Key('trailer-volume-slider'));
    tester.widget<Slider>(slider).onChanged!(70);
    await tester.pump();
    expect(engine.volumes.last, 70);
    expect(
      ProviderScope.containerOf(tester.element(slider))
          .read(playerVolumeProvider),
      70,
    );
  });

  testWidgets('muteToggles', (tester) async {
    await pumpTrailer(tester, volume: 60);
    await tester.tap(find.byTooltip('Disattiva audio'));
    await tester.pump();
    expect(engine.volumes.last, 0);
    await tester.tap(find.byTooltip('Riattiva audio'));
    await tester.pump();
    expect(engine.volumes.last, 60);
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('trailer-volume-slider'))));
    expect(container.read(playerVolumeProvider), 60);
  });

  testWidgets('arrowKeysChangeVolume', (tester) async {
    await pumpTrailer(tester, volume: 50);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(engine.volumes.last, 50 + volumeStep);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.volumes.last, 50 - volumeStep);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumes.last, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumes.last, 50 - volumeStep);
  });

  testWidgets('noSliderOnTouch', (tester) async {
    await pumpTrailer(tester, touch: true);
    expect(find.byKey(const Key('trailer-volume-slider')), findsNothing);
    expect(find.byTooltip('Disattiva audio'), findsOneWidget);
  });

  testWidgets('noVolumeControlsOnTv', (tester) async {
    await pumpTrailer(tester, tv: true);
    expect(find.byKey(const Key('trailer-volume-slider')), findsNothing);
    expect(find.byTooltip('Disattiva audio'), findsNothing);

    // Le frecce su/giù e M restano com'erano: nessun cambio di volume.
    final before = engine.volumes.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumes.length, before);
  });

  testWidgets('noVolumeKeysWhenUnavailable', (tester) async {
    api.startResult = const TrailerStatus('k1', TrailerState.failed);
    await pumpTrailer(tester, volume: 50);
    expect(find.text('Trailer non disponibile'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumes, isEmpty);
    expect(
      ProviderScope.containerOf(tester.element(find.text('Chiudi')))
          .read(playerVolumeProvider),
      50,
    );
  });

  testWidgets('muteDuringOpenStaysMuted', (tester) async {
    final slow = _SlowOpenEngine();
    engine = slow;
    await pumpTrailer(tester, volume: 60);
    expect(engine.calls, ['open']);
    await tester.tap(find.byTooltip('Disattiva audio'));
    await tester.pump();
    slow.finishOpen();
    await tester.pump();
    await tester.pump();
    expect(engine.calls, ['open', 'play']);
    expect(engine.volumes.last, 0);
  });
}

/// Ricorda quanti volumi erano già stati impostati quando parte `play()`.
class _OrderedEngine extends FakeVideoEngine {
  int volumesAtPlay = -1;

  @override
  Future<void> play() async {
    volumesAtPlay = volumes.length;
    await super.play();
  }
}

/// `open` resta in attesa finché il test non la completa.
class _SlowOpenEngine extends FakeVideoEngine {
  final _gate = Completer<void>();

  void finishOpen() => _gate.complete();

  @override
  Future<void> open(VideoSource source) async {
    await super.open(source);
    await _gate.future;
  }
}
