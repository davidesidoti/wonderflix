import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_api.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/media_session/media_session.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/player_window.dart';

/// Stream del file di prova, come li restituisce Jellyfin. In transcodifica
/// il server consegna a parte i sottotitoli testuali e brucia nel video
/// quelli grafici.
List<Map<String, dynamic>> testStreams({bool transcode = false}) => [
      {'Index': 0, 'Type': 'Video', 'Codec': 'hevc'},
      {
        'Index': 1,
        'Type': 'Audio',
        'Codec': 'eac3',
        'Language': 'ita',
        'DisplayTitle': 'Italiano - E-AC3 5.1',
        'IsDefault': true,
      },
      {
        'Index': 2,
        'Type': 'Audio',
        'Codec': 'aac',
        'Language': 'eng',
        'DisplayTitle': 'English - AAC Stereo',
      },
      {
        'Index': 3,
        'Type': 'Subtitle',
        'Codec': 'ass',
        'Language': 'ita',
        'DisplayTitle': 'Italiano - ASS',
        'IsTextSubtitleStream': true,
        'DeliveryMethod': transcode ? 'External' : 'Embed',
        'DeliveryUrl':
            ?(transcode ? '/Videos/m1/ms1/Subtitles/3/0/Stream.ass' : null),
      },
      {
        'Index': 4,
        'Type': 'Subtitle',
        'Codec': 'PGSSUB',
        'Language': 'eng',
        'DisplayTitle': 'English - PGS',
        'DeliveryMethod': transcode ? 'Encode' : 'Embed',
      },
      {
        'Index': 5,
        'Type': 'Subtitle',
        'Codec': 'srt',
        'Language': 'ita',
        'DisplayTitle': 'Italiano - SRT - Esterno',
        'IsExternal': true,
        'IsTextSubtitleStream': true,
        'DeliveryMethod': 'External',
        'DeliveryUrl': '/Videos/m1/ms1/Subtitles/5/0/Stream.srt',
      },
      // Sottotitolo grafico esterno (.sup): il server lo può solo bruciare nel
      // video, anche in direct play.
      {
        'Index': 6,
        'Type': 'Subtitle',
        'Codec': 'PGSSUB',
        'Language': 'ita',
        'DisplayTitle': 'Italiano - PGS - Esterno',
        'IsExternal': true,
        'DeliveryMethod': 'Encode',
      },
    ];

/// Risposta di PlaybackInfo per il file di prova: sorgente `ms1`, sessione
/// `ps1`, audio predefinito 1, sottotitolo predefinito [defaultSubtitle].
PlaybackInfoResult testPlaybackInfo({
  bool directPlay = true,
  int? defaultSubtitle = 3,
  String? errorCode,
}) =>
    PlaybackInfoResult.fromJson({
      'PlaySessionId': 'ps1',
      'ErrorCode': ?errorCode,
      'MediaSources': [
        {
          'Id': 'ms1',
          'SupportsDirectPlay': directPlay,
          'SupportsDirectStream': directPlay,
          'TranscodingUrl': ?(directPlay
              ? null
              : '/videos/m1/master.m3u8?MediaSourceId=ms1&PlaySessionId=ps1'),
          'DefaultAudioStreamIndex': 1,
          'DefaultSubtitleStreamIndex': defaultSubtitle ?? -1,
          'MediaStreams': testStreams(transcode: !directPlay),
        },
      ],
    });

/// Tracce che mpv mostrerebbe per il file di prova in direct play: id
/// numerati per tipo, `ff-index` uguale all'`Index` di Jellyfin.
const testEngineTracks = [
  EngineTrack(id: '1', type: EngineTrackType.video, ffIndex: 0),
  EngineTrack(id: '1', type: EngineTrackType.audio, ffIndex: 1, language: 'ita'),
  EngineTrack(id: '2', type: EngineTrackType.audio, ffIndex: 2, language: 'eng'),
  EngineTrack(
      id: '1', type: EngineTrackType.subtitle, ffIndex: 3, language: 'ita'),
  EngineTrack(
      id: '2', type: EngineTrackType.subtitle, ffIndex: 4, language: 'eng'),
];

typedef PlaybackInfoCall = ({
  String itemId,
  Duration start,
  bool allowDirect,
  int maxBitrate,
  String? mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
});

/// `PlaybackApi` in memoria: risposte configurabili e chiamate registrate.
class FakePlaybackApi implements PlaybackApi {
  /// Di default risponde come il server: direct play se consentito,
  /// altrimenti transcodifica.
  PlaybackInfoResult Function(PlaybackInfoCall call) onPlaybackInfo =
      (call) => testPlaybackInfo(directPlay: call.allowDirect);
  UserItemData userDataResult = const UserItemData();

  /// Se valorizzato, ogni chiamata lancia questo errore (dopo averla
  /// registrata).
  Object? error;

  /// Ritardo simulato di ogni risposta.
  Duration delay = Duration.zero;

  final playbackInfoCalls = <PlaybackInfoCall>[];
  final started = <PlaybackReport>[];
  final progress = <PlaybackReport>[];
  final stopped = <PlaybackReport>[];
  final userDataCalls = <String>[];

  /// Segmenti restituiti da [mediaSegments].
  List<MediaSegment> segments = const [];

  /// Se valorizzato, solo [mediaSegments] lancia questo errore.
  Object? segmentsError;
  final segmentsCalls = <String>[];

  @override
  Future<List<MediaSegment>> mediaSegments(String itemId) async {
    segmentsCalls.add(itemId);
    final failure = segmentsError;
    if (failure != null) throw failure;
    return segments;
  }

  Future<T> _answer<T>(T Function() value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = error;
    if (failure != null) throw failure;
    return value();
  }

  @override
  Future<PlaybackInfoResult> playbackInfo(
    String itemId, {
    required String userId,
    required Duration start,
    required int maxBitrate,
    required bool allowDirect,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final call = (
      itemId: itemId,
      start: start,
      allowDirect: allowDirect,
      maxBitrate: maxBitrate,
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
    playbackInfoCalls.add(call);
    return _answer(() => onPlaybackInfo(call));
  }

  @override
  Future<void> reportStart(PlaybackReport report) {
    started.add(report);
    return _answer(() {});
  }

  @override
  Future<void> reportProgress(PlaybackReport report) {
    progress.add(report);
    return _answer(() {});
  }

  @override
  Future<void> reportStopped(PlaybackReport report) {
    stopped.add(report);
    return _answer(() {});
  }

  @override
  Future<UserItemData> userData(String userId, String itemId) {
    userDataCalls.add(itemId);
    return _answer(() => userDataResult);
  }
}

/// Motore video in memoria: registra i comandi e simula gli eventi di mpv.
class FakeVideoEngine implements VideoEngine {
  /// Quante delle prossime aperture devono fallire.
  int failOpens = 0;
  List<EngineTrack> engineTracks = const [];

  /// I sottotitoli esterni non si caricano (`addSubtitle` restituisce `null`).
  bool failAddSubtitle = false;

  /// Se valorizzato, `addSubtitle` resta in attesa finché non si completa.
  Completer<void>? addSubtitleGate;

  final opened = <VideoSource>[];

  /// Comandi ricevuti, in ordine (es. `open`, `audio 1`, `play`).
  final calls = <String>[];
  final selectedAudio = <String?>[];
  final selectedSubtitle = <String?>[];
  final addedSubtitles = <String>[];
  final subtitleDelays = <Duration>[];

  /// Non registrato in [calls].
  final subtitleScales = <double>[];
  final seeks = <Duration>[];
  final volumes = <double>[];
  bool disposed = false;
  int _nextSubtitleId = 100;

  Duration _position = Duration.zero;
  Duration _duration = const Duration(hours: 2);
  Duration _buffer = Duration.zero;
  bool _playing = false;

  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _buffers = StreamController<Duration>.broadcast();
  final _playingEvents = StreamController<bool>.broadcast();
  final _bufferingEvents = StreamController<bool>.broadcast();
  final _completedEvents = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();

  void emitPosition(Duration position) {
    _position = position;
    _positions.add(position);
  }

  void emitDuration(Duration duration) {
    _duration = duration;
    _durations.add(duration);
  }

  void emitBuffer(Duration buffer) {
    _buffer = buffer;
    _buffers.add(buffer);
  }

  void emitBuffering(bool buffering) => _bufferingEvents.add(buffering);

  void emitError(String message) => _errors.add(message);

  void emitCompleted() {
    _setPlaying(false);
    _completedEvents.add(true);
  }

  void _setPlaying(bool playing) {
    _playing = playing;
    _playingEvents.add(playing);
  }

  @override
  Future<void> open(VideoSource source) async {
    opened.add(source);
    calls.add('open');
    if (failOpens > 0) {
      failOpens--;
      throw const EngineOpenException('apertura simulata non riuscita');
    }
    // Come mpv: il file si apre in pausa.
    _position = source.start;
    _setPlaying(false);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _setPlaying(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    emitPosition(position);
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<List<EngineTrack>> tracks() async => engineTracks;

  @override
  Future<void> selectAudio(String? id) async {
    calls.add('audio $id');
    selectedAudio.add(id);
  }

  @override
  Future<void> selectSubtitle(String? id) async {
    calls.add('subtitle $id');
    selectedSubtitle.add(id);
  }

  @override
  Future<String?> addSubtitle(String url,
      {String? title, String? language}) async {
    calls.add('add $url');
    addedSubtitles.add(url);
    await addSubtitleGate?.future;
    // Come mpv quando `sub-add` fallisce: resta selezionato quello di prima.
    if (failAddSubtitle) return null;
    final id = '${_nextSubtitleId++}';
    selectedSubtitle.add(id);
    return id;
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async =>
      subtitleDelays.add(delay);

  @override
  Future<void> setSubtitleScale(double scale) async =>
      subtitleScales.add(scale);

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Duration get buffer => _buffer;

  @override
  bool get playing => _playing;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration> get durationStream => _durations.stream;

  @override
  Stream<Duration> get bufferStream => _buffers.stream;

  @override
  Stream<bool> get playingStream => _playingEvents.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingEvents.stream;

  @override
  Stream<bool> get completedStream => _completedEvents.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Widget buildView() =>
      const ColoredBox(key: Key('fake-video'), color: Color(0xFF000000));
}

/// Finestra in memoria: registra le chiamate e simula la chiusura.
class FakePlayerWindow implements PlayerWindow {
  final fullScreenCalls = <bool>[];
  final preventCloseCalls = <bool>[];
  bool destroyed = false;
  final _closeListeners = <Future<void> Function()>[];

  @override
  Future<void> setFullScreen(bool value) async => fullScreenCalls.add(value);

  @override
  Future<void> setPreventClose(bool value) async =>
      preventCloseCalls.add(value);

  @override
  Future<void> destroy() async {
    destroyed = true;
  }

  @override
  void addCloseListener(Future<void> Function() onClose) =>
      _closeListeners.add(onClose);

  @override
  void removeCloseListener(Future<void> Function() onClose) =>
      _closeListeners.remove(onClose);

  /// Simula il clic sulla X della finestra.
  Future<void> simulateClose() =>
      Future.wait([for (final listener in [..._closeListeners]) listener()]);
}

/// Impostazioni del player in memoria (senza shared_preferences).
class FakePlayerSettings extends PlayerSettingsController {
  FakePlayerSettings([this.initial = const PlayerSettings()]);

  final PlayerSettings initial;

  @override
  PlayerSettings build() => initial;

  @override
  Future<void> update(PlayerSettings next) async {
    state = next;
  }
}

/// PNG trasparente 1×1, per sostituire le immagini di rete nei test.
const transparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// Sessione media in memoria: registra gli aggiornamenti e simula i tasti.
class FakeMediaSession implements MediaSession {
  final metadata = <({String title, String? subtitle, String? thumbnailUrl})>[];
  final playingStates = <bool>[];
  final timelines = <Duration>[];
  final nextEnabled = <bool>[];

  /// Volte in cui il pannello è stato nascosto ([clear]).
  int cleared = 0;
  bool disposed = false;

  @override
  bool handlesMediaKeys = false;
  final _buttons = StreamController<MediaButton>.broadcast();

  void press(MediaButton button) => _buttons.add(button);

  @override
  Future<void> setMetadata(
      {required String title, String? subtitle, String? thumbnailUrl}) async {
    metadata.add((title: title, subtitle: subtitle, thumbnailUrl: thumbnailUrl));
  }

  @override
  Future<void> setPlaying(bool playing) async => playingStates.add(playing);

  @override
  Future<void> setTimeline(
          {required Duration position, required Duration duration}) async =>
      timelines.add(position);

  @override
  Future<void> setNextEnabled(bool enabled) async => nextEnabled.add(enabled);

  @override
  Stream<MediaButton> get buttons => _buttons.stream;

  @override
  Future<void> clear() async => cleared++;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
