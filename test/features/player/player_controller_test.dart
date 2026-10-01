import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/features/player/playback_authority.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/segments.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakePlaybackApi playback;
  late FakeVideoEngine engine;
  late ProviderContainer container;
  var settings = const PlayerSettings();
  const args = (itemId: 'm1', start: Duration(minutes: 3), party: null);
  final provider = playerControllerProvider(args);

  setUp(() {
    settings = const PlayerSettings();
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
        playerSettingsProvider.overrideWith(() => FakePlayerSettings(settings)),
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
    // Il file si apre in pausa e parte solo con le tracce già scelte.
    expect(engine.calls, ['open', 'audio 1', 'subtitle 1', 'play']);
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

  test('close(watched: true): episodio segnato come visto', () async {
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 119));
    playback.userDataResult = const UserItemData(played: true);

    await controller.close(watched: true);
    expect(playback.stopped.single.position, const Duration(minutes: 119));
    expect(library.playedCalls, [('m1', true)]);
    expect(container.read(userDataOverridesProvider)['m1']?.played, isTrue);
    expect(container.read(userDataRevisionProvider), 1);
  });

  test('close senza watched: nessun "visto"', () async {
    final controller = await start();
    await controller.close();
    expect(library.playedCalls, isEmpty);
  });

  test('close(watched: true) senza rete: minutaggio aggiornato lo stesso',
      () async {
    final controller = await start();
    library.error = const ServerUnreachableException();
    await controller.close(watched: true);
    expect(library.playedCalls, [('m1', true)]);
    expect(container.read(userDataRevisionProvider), 1);
  });

  test('watched chiesto mentre la chiusura è già partita', () async {
    final controller = await start();
    final closing = controller.close();
    await controller.close(watched: true);
    await closing;
    expect(library.playedCalls, [('m1', true)]);
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

  test('sottotitoli: esterno caricato una volta, interni, nessuno', () async {
    final controller = await start();
    await controller.selectSubtitle(5);
    expect(engine.addedSubtitles,
        ['https://media.example.com/Videos/m1/ms1/Subtitles/5/0/Stream.srt']);
    expect(view().subtitleIndex, 5);

    await controller.selectSubtitle(4);
    expect(engine.selectedSubtitle.last, '2');

    await controller.selectSubtitle(5);
    expect(engine.addedSubtitles, hasLength(1), reason: 'già caricato');
    expect(engine.selectedSubtitle.last, '100');

    await controller.selectSubtitle(null);
    expect(engine.selectedSubtitle.last, isNull);
    expect(view().subtitleIndex, isNull);
    expect(playback.progress, isNotEmpty);
  });

  const assUrl = 'https://media.example.com/Videos/m1/ms1/Subtitles/3/0/Stream.ass';
  const srtUrl = 'https://media.example.com/Videos/m1/ms1/Subtitles/5/0/Stream.srt';

  test('sottotitolo consegnato a parte: caricato dopo la partenza', () async {
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final gate = engine.addSubtitleGate = Completer<void>();
    await start();
    expect(view().status, PlayerStatus.ready);
    expect(view().playing, isTrue);
    expect(playback.started, hasLength(1));
    expect(engine.calls, ['open', 'subtitle null', 'play', 'add $assUrl']);

    gate.complete();
    await pumpEventQueue();
    expect(engine.selectedSubtitle.last, '100');
    expect(view().subtitleIndex, 3);
  });

  test('sottotitolo iniziale non caricato: nessun sottotitolo', () async {
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    engine.failAddSubtitle = true;
    await start();
    expect(view().status, PlayerStatus.ready);
    expect(engine.addedSubtitles, [assUrl]);
    expect(view().subtitleIndex, isNull);
  });

  test('scelta durante il caricamento iniziale: vince quella dell\'utente',
      () async {
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final gate = engine.addSubtitleGate = Completer<void>();
    final controller = await start();
    final choice = controller.selectSubtitle(null);
    await pumpEventQueue();
    gate.complete();
    await choice;
    expect(engine.calls.last, 'subtitle null');
    expect(view().subtitleIndex, isNull);
  });

  test('sottotitolo esterno non caricato: resta quello di prima', () async {
    final controller = await start();
    engine.failAddSubtitle = true;
    await controller.selectSubtitle(5);
    expect(engine.addedSubtitles, [srtUrl]);
    expect(engine.selectedSubtitle, ['1']);
    expect(view().subtitleIndex, 3);
  });

  test('due scelte rapide: applicate una dopo l\'altra', () async {
    final controller = await start();
    final gate = engine.addSubtitleGate = Completer<void>();
    final first = controller.selectSubtitle(5);
    final second = controller.selectSubtitle(4);
    await pumpEventQueue();
    gate.complete();
    await Future.wait([first, second]);
    expect(engine.selectedSubtitle.last, '2');
    expect(view().subtitleIndex, 4);
  });

  test('audio in direct play: cambia traccia senza riaprire', () async {
    final controller = await start();
    await controller.selectAudio(2);
    expect(engine.selectedAudio.last, '2');
    expect(view().audioIndex, 2);
    expect(engine.opened, hasLength(1));
  });

  test('audio in transcodifica: riapre la conversione dal punto attuale',
      () async {
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 10));

    await controller.selectAudio(2);
    await pumpEventQueue();
    final call = playback.playbackInfoCalls.last;
    expect(call.allowDirect, isFalse);
    expect(call.audioStreamIndex, 2);
    expect(call.subtitleStreamIndex, 3);
    expect(call.start, const Duration(minutes: 10));
    expect(engine.opened, hasLength(2));
    expect(playback.stopped, hasLength(1),
        reason: 'la sessione precedente viene chiusa');
    expect(view().audioIndex, 2);
    expect(view().status, PlayerStatus.ready);
  });

  test('Riprova dopo un cambio di traccia non riuscito: tiene la scelta',
      () async {
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 10));
    engine.failOpens = 1;

    await controller.selectAudio(2);
    expect(view().status, PlayerStatus.error);

    await controller.retry();
    final call = playback.playbackInfoCalls.last;
    expect(call.allowDirect, isFalse);
    expect(call.audioStreamIndex, 2);
    expect(call.subtitleStreamIndex, 3);
    expect(call.start, const Duration(minutes: 10));
    expect(view().status, PlayerStatus.ready);
    expect(view().audioIndex, 2);
  });

  test('transcodifica: un sottotitolo bruciato richiede una nuova conversione',
      () async {
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final controller = await start();

    await controller.selectSubtitle(4);
    expect(playback.playbackInfoCalls.last.subtitleStreamIndex, 4);
    expect(engine.opened, hasLength(2));
    expect(view().subtitleIndex, 4);

    await controller.selectSubtitle(null);
    expect(playback.playbackInfoCalls.last.subtitleStreamIndex, -1);
    expect(engine.opened, hasLength(3));
    expect(view().subtitleIndex, isNull);
  });

  test('direct play: un sottotitolo da bruciare passa alla transcodifica',
      () async {
    final controller = await start();
    engine.emitPosition(const Duration(minutes: 7));

    await controller.selectSubtitle(6);
    final call = playback.playbackInfoCalls.last;
    expect(call.allowDirect, isFalse);
    expect(call.subtitleStreamIndex, 6);
    expect(call.audioStreamIndex, 1);
    expect(call.start, const Duration(minutes: 7));
    expect(engine.opened, hasLength(2));
    expect(view().plan?.isTranscode, isTrue);
    expect(view().subtitleIndex, 6);
    expect(view().status, PlayerStatus.ready);
  });

  test('comandi: pausa, salti nei limiti, volume, muto, ritardo', () async {
    final controller = await start();
    await controller.togglePlay();
    expect(engine.playing, isFalse);
    await controller.togglePlay();
    expect(engine.playing, isTrue);

    await controller.seekBy(const Duration(minutes: -10));
    expect(engine.seeks.last, Duration.zero);
    await controller.seekTo(const Duration(hours: 3));
    expect(engine.seeks.last, const Duration(hours: 2));

    await controller.setVolume(150);
    expect(engine.volumes.last, 100);
    await controller.changeVolumeBy(-5);
    expect(engine.volumes.last, 95);
    await controller.toggleMute();
    expect(engine.volumes.last, 0);
    expect(view().muted, isTrue);
    await controller.toggleMute();
    expect(engine.volumes.last, 95);

    await controller.shiftSubtitleDelay(const Duration(milliseconds: 100));
    await controller.shiftSubtitleDelay(const Duration(milliseconds: 100));
    expect(engine.subtitleDelays.last, const Duration(milliseconds: 200));
    expect(view().subtitleDelay, const Duration(milliseconds: 200));
  });

  test('play e pause: idempotenti; prima della partenza non fanno nulla',
      () async {
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await controller.pause();
    expect(engine.calls, isNot(contains('pause')));
    await pumpEventQueue();

    await controller.pause();
    await controller.pause();
    expect(engine.playing, isFalse);
    await controller.play();
    await controller.play();
    expect(engine.playing, isTrue);
  });

  test('qualità scelta: bitrate massimo nella richiesta', () async {
    settings = const PlayerSettings(quality: StreamQuality.mbps8);
    await start();
    expect(playback.playbackInfoCalls.first.maxBitrate, 8000000);
  });

  test('dimensione dei sottotitoli applicata all\'apertura', () async {
    settings = const PlayerSettings(subtitleScale: 1.25);
    await start();
    expect(engine.subtitleScales, [1.25]);
  });

  test('dimensione normale: nessuna modifica', () async {
    await start();
    expect(engine.subtitleScales, isEmpty);
  });

  test('segmenti ed episodio successivo caricati dopo la partenza', () async {
    library.itemsById['m1'] =
        testItem(id: 'm1', kind: ItemKind.episode, seriesId: 's1');
    library.nextEpisodes['m1'] =
        testItem(id: 'm2', kind: ItemKind.episode, seriesId: 's1');
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    await start();
    expect(view().segments.single.type, MediaSegmentType.intro);
    expect(view().nextEpisode?.id, 'm2');
    expect(library.nextEpisodeCalls, ['m1']);
    expect(playback.segmentsCalls, ['m1']);
  });

  test('film: nessun episodio successivo; segmenti non disponibili ignorati',
      () async {
    playback.segmentsError = const ServerUnreachableException();
    await start();
    expect(view().status, PlayerStatus.ready);
    expect(view().segments, isEmpty);
    expect(view().nextEpisode, isNull);
    expect(library.nextEpisodeCalls, isEmpty);
  });

  test('salta il segmento in corso', () async {
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.recap,
          start: Duration.zero,
          end: Duration(seconds: 60)),
    ];
    final controller = await start();
    engine.emitPosition(const Duration(seconds: 5));
    await controller.skipCurrentSegment();
    expect(engine.seeks.last, const Duration(seconds: 60));
  });

  test('salto automatico dell\'intro: una volta sola', () async {
    settings = const PlayerSettings(autoSkipIntro: true);
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    await start();
    engine.emitPosition(const Duration(seconds: 20));
    await pumpEventQueue();
    expect(engine.seeks, [const Duration(seconds: 90)]);

    // Tornando indietro nell'intro non la salta più.
    engine.emitPosition(const Duration(seconds: 30));
    await pumpEventQueue();
    expect(engine.seeks, hasLength(1));
  });

  test('salto automatico: lo segnala (per la pillola)', () async {
    settings = const PlayerSettings(autoSkipIntro: true);
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    final controller = await start();
    final skips = <SkipKind>[];
    final subscription = controller.autoSkips.listen(skips.add);
    addTearDown(subscription.cancel);
    engine.emitPosition(const Duration(seconds: 20));
    await pumpEventQueue();
    expect(skips, [SkipKind.intro]);
  });

  test('salto automatico spento: nessun salto', () async {
    playback.segments = const [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 10),
          end: Duration(seconds: 90)),
    ];
    await start();
    engine.emitPosition(const Duration(seconds: 20));
    await pumpEventQueue();
    expect(engine.seeks, isEmpty);
  });

  group('watch party', () {
    const partyArgs =
        (itemId: 'm1', start: Duration(minutes: 3), party: 'p1');
    final partyProvider = playerControllerProvider(partyArgs);

    Future<PlayerController> startParty() async {
      container.listen(partyProvider, (_, _) {});
      await pumpEventQueue();
      return container.read(partyProvider.notifier);
    }

    test('il file si apre in pausa e non parte da solo', () async {
      final controller = await startParty();
      expect(controller.inParty, isTrue);
      expect(container.read(partyProvider).status, PlayerStatus.ready);
      expect(engine.opened.single.start, const Duration(minutes: 3));
      expect(engine.calls, isNot(contains('play')));
      expect(container.read(partyProvider).playing, isFalse);
    });

    test('pausa, ripresa e salti passano per l\'autorità', () async {
      final controller = await startParty();
      final authority = RecordingAuthority();
      controller.setAuthority(authority);
      await controller.togglePlay();
      await controller.seekTo(const Duration(hours: 5));
      await controller.seekBy(const Duration(seconds: -10));
      await controller.pause();
      await controller.play();
      expect(authority.calls, [
        'play',
        'seek ${const Duration(hours: 2)}',
        'seek ${const Duration(minutes: 2, seconds: 50)}',
        'pause',
        'play',
      ]);
      expect(engine.seeks, isEmpty);

      // Senza autorità si torna al motore.
      controller.setAuthority(null);
      await controller.seekTo(const Duration(minutes: 1));
      expect(engine.seeks, [const Duration(minutes: 1)]);
    });

    test('niente salto automatico dell\'intro', () async {
      settings = const PlayerSettings(autoSkipIntro: true);
      playback.segments = const [
        MediaSegment(
            type: MediaSegmentType.intro,
            start: Duration(seconds: 10),
            end: Duration(seconds: 90)),
      ];
      await startParty();
      engine.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();
      expect(engine.seeks, isEmpty);
    });

    test('leaveParty: di nuovo da solo (salto dell\'intro, partenza)',
        () async {
      settings = const PlayerSettings(autoSkipIntro: true);
      playback.segments = const [
        MediaSegment(
            type: MediaSegmentType.intro,
            start: Duration(seconds: 10),
            end: Duration(seconds: 90)),
      ];
      final controller = await startParty();
      controller.leaveParty();
      expect(controller.inParty, isFalse);
      engine.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();
      expect(engine.seeks, [const Duration(seconds: 90)]);

      engine.calls.clear();
      await controller.retry();
      await pumpEventQueue();
      expect(engine.calls, contains('play'));
    });
  });

  test('dimensione dei sottotitoli dal pannello: subito e salvata', () async {
    final controller = await start();
    await controller.setSubtitleScale(1.25);
    expect(engine.subtitleScales.last, 1.25);
    expect(container.read(playerSettingsProvider).subtitleScale, 1.25);

    // "Riprova" riapre con la dimensione nuova.
    await controller.retry();
    await pumpEventQueue();
    expect(engine.subtitleScales, [1.25, 1.25],
        reason: 'la riapertura applica di nuovo la dimensione');
  });
}

/// Autorità che registra le richieste invece di muovere il motore.
class RecordingAuthority implements PlaybackAuthority {
  final calls = <String>[];

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seekTo(Duration position) async => calls.add('seek $position');
}
