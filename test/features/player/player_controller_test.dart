import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakePlaybackApi playback;
  late FakeVideoEngine engine;
  late ProviderContainer container;
  const args = (itemId: 'm1', start: Duration(minutes: 3));
  final provider = playerControllerProvider(args);

  setUp(() {
    library = FakeLibraryApi()
      ..itemsById['m1'] = testItem(id: 'm1', runtimeMinutes: 120);
    playback = FakePlaybackApi();
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(PlaybackService(
          api: playback,
          serverUrl: testServerUrl,
          authorization: () => 'MediaBrowser Token="t1"',
        )),
        videoEngineFactoryProvider.overrideWithValue(() => engine),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
  });

  /// Monta il controller (come fa la schermata) e aspetta l'avvio.
  Future<PlayerController> start() async {
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return container.read(provider.notifier);
  }

  PlayerViewState view() => container.read(provider);

  test('direct play: stream con header, ripresa e tracce predefinite',
      () async {
    await start();
    expect(view().status, PlayerStatus.ready);
    expect(view().item?.id, 'm1');
    final source = engine.opened.single;
    expect(source.url,
        'https://media.example.com/Videos/m1/stream?static=true&mediaSourceId=ms1&playSessionId=ps1');
    expect(source.headers, {'Authorization': 'MediaBrowser Token="t1"'});
    expect(source.start, const Duration(minutes: 3));
    expect(engine.selectedAudio, ['1']);
    expect(engine.selectedSubtitle, ['1']);
    expect(view().audioIndex, 1);
    expect(view().subtitleIndex, 3);
    expect(view().playing, isTrue);
    final started = playback.started.single;
    expect(started.playMethod, PlayMethod.directPlay);
    expect(started.playSessionId, 'ps1');
    expect(started.position, const Duration(minutes: 3));
  });

  test('direct play non riuscito: un solo tentativo in transcodifica',
      () async {
    engine.failOpens = 1;
    await start();
    expect(playback.playbackInfoCalls.map((c) => c.allowDirect), [true, false]);
    final retry = playback.playbackInfoCalls.last;
    expect(retry.mediaSourceId, 'ms1');
    expect(retry.audioStreamIndex, 1);
    expect(retry.subtitleStreamIndex, 3);
    expect(retry.start, const Duration(minutes: 3));
    expect(engine.opened, hasLength(2));
    expect(engine.opened.last.url,
        'https://media.example.com/videos/m1/master.m3u8?MediaSourceId=ms1&PlaySessionId=ps1');
    expect(view().status, PlayerStatus.ready);
    expect(view().transcodingFallback, isTrue);
    // Sottotitolo testuale estratto dal server: caricato a parte.
    expect(engine.addedSubtitles,
        ['https://media.example.com/Videos/m1/ms1/Subtitles/3/0/Stream.ass']);
    expect(playback.started.single.playMethod, PlayMethod.transcode);
  });

  test('anche la transcodifica fallisce: errore, poi Riprova', () async {
    engine.failOpens = 2;
    final controller = await start();
    expect(view().status, PlayerStatus.error);
    expect(view().error, isA<EngineOpenException>());
    expect(playback.playbackInfoCalls, hasLength(2), reason: 'un solo ripiego');

    await controller.retry();
    expect(view().status, PlayerStatus.ready);
    expect(view().error, isNull);
    expect(playback.playbackInfoCalls.last.allowDirect, isFalse);
  });

  test('errore del server: nessuna apertura', () async {
    playback.error = const ServerUnreachableException();
    await start();
    expect(view().status, PlayerStatus.error);
    expect(view().error, isA<ServerUnreachableException>());
    expect(engine.opened, isEmpty);
  });

  test('fine del video', () async {
    await start();
    engine.emitCompleted();
    await pumpEventQueue();
    expect(view().finished, isTrue);
  });

  test('close: fine della sessione, motore liberato, minutaggio aggiornato',
      () async {
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 60));
    playback.userDataResult = const UserItemData(
        playbackPositionTicks: 36000000000, playedPercentage: 50);

    await controller.close();
    expect(playback.stopped.single.position, const Duration(minutes: 60));
    expect(engine.disposed, isTrue);
    expect(playback.userDataCalls, ['m1']);
    expect(container.read(userDataOverridesProvider)['m1']?.playbackPositionTicks,
        36000000000);
    expect(container.read(userDataRevisionProvider), 1);

    await controller.close();
    expect(playback.stopped, hasLength(1));
  });

  test('close senza rete: stima locale del minutaggio', () async {
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 30));
    playback.error = const ServerUnreachableException();

    await controller.close();
    final data = container.read(userDataOverridesProvider)['m1'];
    expect(data?.playbackPositionTicks,
        durationToTicks(const Duration(minutes: 30)));
    expect(data?.playedPercentage, 25);
    expect(container.read(userDataRevisionProvider), 1);
  });

  test('uscita dalla schermata: la dispose chiude la riproduzione', () async {
    final subscription = container.listen(provider, (_, _) {});
    await pumpEventQueue();
    subscription.close();
    await pumpEventQueue();
    expect(playback.stopped, hasLength(1));
    expect(engine.disposed, isTrue);
  });
}
