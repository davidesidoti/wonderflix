import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/player_volume.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/test_data.dart';

/// Sottotitolo esterno appena scaricato, con l'indice [index].
Map<String, dynamic> _newExternal(int index) => {
      'Index': index,
      'Type': 'Subtitle',
      'Codec': 'srt',
      'Language': 'eng',
      'DisplayTitle': 'English - SRT - Esterno',
      'IsExternal': true,
      'IsTextSubtitleStream': true,
      'DeliveryMethod': 'External',
      'DeliveryUrl': '/Videos/m1/ms1/Subtitles/$index/0/Stream.srt',
    };

/// PlaybackInfo del file di prova (sorgente `ms1`) con le tracce [streams].
PlaybackInfoResult _infoWith(List<Map<String, dynamic>> streams,
        {bool directPlay = true}) =>
    PlaybackInfoResult.fromJson({
      'PlaySessionId': 'ps2',
      'MediaSources': [
        {
          'Id': 'ms1',
          'SupportsDirectPlay': directPlay,
          'TranscodingUrl': ?(directPlay
              ? null
              : '/videos/m1/master.m3u8?MediaSourceId=ms1&PlaySessionId=ps2'),
          'DefaultAudioStreamIndex': 1,
          'DefaultSubtitleStreamIndex': 3,
          'MediaStreams': streams,
        },
      ],
    });

void main() {
  late FakePlaybackApi playback;
  late FakeVideoEngine engine;
  late ProviderContainer container;
  const args = (itemId: 'm1', start: Duration(minutes: 3), party: null);
  final provider = playerControllerProvider(args);

  setUp(() {
    playback = FakePlaybackApi();
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(FakeLibraryApi()
          ..itemsById['m1'] = testItem(id: 'm1', runtimeMinutes: 120)),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(PlaybackService(
          api: playback,
          serverUrl: testServerUrl,
          authorization: () => 'MediaBrowser Token="t1"',
        )),
        videoEngineFactoryProvider.overrideWithValue(() => engine),
        playerSettingsProvider.overrideWith(FakePlayerSettings.new),
        playerVolumeProvider.overrideWith(FakePlayerVolume.new),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
  });

  Future<PlayerController> start() async {
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return container.read(provider.notifier);
  }

  PlayerViewState view() => container.read(provider);

  test('traccia esterna nuova: added e la lista la mostra senza ripartire',
      () async {
    final controller = await start();
    final before = view().plan!;
    playback.onPlaybackInfo = (_) => _infoWith([...testStreams(), _newExternal(7)]);

    expect(await controller.refreshSubtitleStreams(), SubtitleRefresh.added);
    // Una sola PlaybackInfo in più, con la stessa versione e le stesse
    // tracce: nessuna nuova apertura.
    expect(playback.playbackInfoCalls, hasLength(2));
    final reload = playback.playbackInfoCalls.last;
    expect(reload.mediaSourceId, 'ms1');
    expect(reload.allowDirect, isTrue);
    expect(reload.audioStreamIndex, 1);
    expect(reload.subtitleStreamIndex, 3);
    expect(engine.opened, hasLength(1));
    final after = view().plan!;
    expect(identical(after.source, before.source), isTrue);
    expect(after.mediaSource.id, 'ms1');
    expect(after.playSessionId, 'ps1');
    expect(after.method, PlayMethod.directPlay);
    expect(view().subtitleIndex, 3);
    expect(view().status, PlayerStatus.ready);
    expect(view().subtitleStreams.map((s) => s.index), [3, 4, 5, 6, 7]);
    // La traccia nuova non si carica finché l'utente non la sceglie.
    expect(engine.addedSubtitles, isEmpty);

    await controller.selectSubtitle(7);
    expect(engine.addedSubtitles,
        ['https://media.example.com/Videos/m1/ms1/Subtitles/7/0/Stream.srt']);
    expect(view().subtitleIndex, 7);
    expect(engine.opened, hasLength(1));
  });

  test('traccia non esterna: messaggio e niente ripartenza', () async {
    // Transcodifica: un sottotitolo grafico nuovo il server lo incide.
    playback.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final controller = await start();
    final before = view().plan!;
    expect(before.isTranscode, isTrue);
    playback.onPlaybackInfo = (_) => _infoWith([
          ...testStreams(transcode: true),
          {
            'Index': 7,
            'Type': 'Subtitle',
            'Codec': 'PGSSUB',
            'Language': 'eng',
            'IsExternal': true,
            'DeliveryMethod': 'Encode',
          },
        ], directPlay: false);

    expect(await controller.refreshSubtitleStreams(),
        SubtitleRefresh.nextPlayback);
    expect(playback.playbackInfoCalls, hasLength(2));
    expect(playback.playbackInfoCalls.last.allowDirect, isFalse);
    expect(engine.opened, hasLength(1));
    expect(identical(view().plan, before), isTrue);
    expect(view().subtitleIndex, 3);
  });

  test('indici di prima spostati → nextPlayback', () async {
    final controller = await start();
    final before = view().plan!;
    final old = testStreams();
    Map<String, dynamic> moved(int from, int to) => {...old[from], 'Index': to};
    // La traccia nuova prende l'indice 1 e le altre scorrono in avanti;
    // l'indice che si aggiunge in fondo (7) è un esterno consegnato a parte,
    // così conta solo lo spostamento.
    playback.onPlaybackInfo = (_) => _infoWith([
          old[0],
          _newExternal(1),
          moved(1, 2),
          moved(2, 3),
          moved(3, 4),
          moved(4, 5),
          moved(6, 6),
          moved(5, 7),
        ]);

    expect(await controller.refreshSubtitleStreams(),
        SubtitleRefresh.nextPlayback);
    expect(identical(view().plan, before), isTrue);
    expect(engine.opened, hasLength(1));
  });

  test('nessuna traccia nuova → unchanged', () async {
    final controller = await start();
    final before = view().plan!;
    expect(await controller.refreshSubtitleStreams(), SubtitleRefresh.unchanged);
    expect(identical(view().plan, before), isTrue);
    expect(engine.opened, hasLength(1));
  });

  test('errore di rete → unchanged', () async {
    final controller = await start();
    final before = view().plan!;
    final logs = <String>[];
    final subscription =
        Logger.root.onRecord.listen((record) => logs.add(record.message));
    addTearDown(subscription.cancel);
    playback.error = const ServerUnreachableException('dettagli riservati');

    expect(await controller.refreshSubtitleStreams(), SubtitleRefresh.unchanged);
    expect(identical(view().plan, before), isTrue);
    expect(view().status, PlayerStatus.ready);
    expect(engine.opened, hasLength(1));
    // Nel log solo il tipo dell'errore.
    expect(logs, contains(contains('ServerUnreachableException')));
    expect(logs, everyElement(isNot(contains('dettagli riservati'))));
  });
}
