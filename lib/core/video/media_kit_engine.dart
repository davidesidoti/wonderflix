import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_engine.dart';

final _log = Logger('player');

/// [VideoEngine] sopra media_kit (libmpv).
/// - Sottotitoli disegnati da libass dentro il video (niente widget Flutter).
/// - Decodifica hardware `auto-safe`.
/// - Tracce lette da mpv (`track-list`), perché media_kit non espone
///   `ff-index`.
class MediaKitEngine implements VideoEngine {
  MediaKitEngine({String hwdec = 'auto-safe'})
      : _player = Player(
          configuration: const PlayerConfiguration(
            title: 'WonderFlix',
            libass: true,
            bufferSize: 64 * 1024 * 1024,
          ),
        ) {
    _video = VideoController(
      _player,
      configuration: VideoControllerConfiguration(hwdec: hwdec),
    );
  }

  /// La transcodifica sul server può impiegare parecchi secondi a partire.
  static const openTimeout = Duration(seconds: 60);

  /// Timeout di rete di mpv (secondi), valido anche per i sottotitoli
  /// caricati a parte.
  static const networkTimeoutSeconds = 60;

  final Player _player;
  late final VideoController _video;
  bool _configured = false;

  NativePlayer get _native => _player.platform! as NativePlayer;

  @override
  Future<void> open(VideoSource source) async {
    await _configure();
    // Azzera lo stato del file precedente (durata compresa) prima di aprire.
    await _player.stop();
    final loaded = Completer<void>();
    // L'eventuale errore viene letto più sotto: evita che risulti "non gestito".
    loaded.future.ignore();
    // Gli errori arrivati prima che l'apertura sia stata chiesta riguardano
    // la chiusura del file precedente, non questo.
    var opened = false;
    final subscriptions = [
      _player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !loaded.isCompleted) loaded.complete();
      }),
      // Un errore prima che la durata sia nota = il file non si è aperto.
      _player.stream.error.listen((message) {
        if (opened && !loaded.isCompleted) {
          loaded.completeError(EngineOpenException(message));
        }
      }),
    ];
    try {
      // In pausa: la riproduzione parte con play(), dopo la scelta delle
      // tracce.
      await _player.open(
        Media(
          source.url,
          httpHeaders: source.headers,
          start: source.start > Duration.zero ? source.start : null,
        ),
        play: false,
      );
      opened = true;
      await loaded.future.timeout(openTimeout,
          onTimeout: () => throw const EngineOpenException('timeout'));
    } on Object {
      // Dopo un errore il file non deve restare caricato (né scaricare dati).
      try {
        await _player.stop();
      } on Object catch (error) {
        _log.warning('stop dopo apertura non riuscita: $error');
      }
      rethrow;
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  /// Opzioni di mpv impostate una volta sola, a player inizializzato: così
  /// non vengono sovrascritte da quelle che media_kit scrive all'avvio.
  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    // media_kit usa 5 s: pochi per l'avvio della transcodifica HLS o per
    // l'estrazione di un sottotitolo su un server lento.
    await _native.setProperty('network-timeout', '$networkTimeoutSeconds');
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  /// Con `PlayerConfiguration.pitch` a `false` media_kit imposta `speed` di
  /// mpv, che mantiene il tono dell'audio (`audio-pitch-correction`).
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<List<EngineTrack>> tracks() async {
    final count =
        int.tryParse(await _native.getProperty('track-list/count')) ?? 0;
    final tracks = <EngineTrack>[];
    for (var i = 0; i < count; i++) {
      Future<String> property(String name) =>
          _native.getProperty('track-list/$i/$name');
      final type = switch (await property('type')) {
        'video' => EngineTrackType.video,
        'audio' => EngineTrackType.audio,
        'sub' => EngineTrackType.subtitle,
        _ => null,
      };
      if (type == null) continue;
      final title = await property('title');
      final language = await property('lang');
      tracks.add(EngineTrack(
        id: await property('id'),
        type: type,
        ffIndex: int.tryParse(await property('ff-index')),
        external: await property('external') == 'yes',
        title: title.isEmpty ? null : title,
        language: language.isEmpty ? null : language,
      ));
    }
    return tracks;
  }

  @override
  Future<void> selectAudio(String? id) =>
      _native.setProperty('aid', id ?? 'no');

  @override
  Future<void> selectSubtitle(String? id) =>
      _native.setProperty('sid', id ?? 'no');

  /// media_kit non segnala se `sub-add` fallisce (lo scrive solo nel log) e
  /// in quel caso `sid` resta il precedente: la traccia aggiunta si cerca
  /// quindi in `track-list`, tra quelle che prima non c'erano.
  @override
  Future<String?> addSubtitle(String url,
      {String? title, String? language}) async {
    final before = {for (final track in await _externalSubtitles()) track.id};
    await _native.command(
        ['sub-add', url, 'select', title ?? 'external', language ?? 'auto']);
    final added = [
      for (final track in await _externalSubtitles())
        if (!before.contains(track.id)) track,
    ];
    for (final track in added) {
      if (track.filename == url) return track.id;
    }
    // mpv potrebbe aver riscritto l'URL: basta che la traccia nuova sia una.
    return added.length == 1 ? added.single.id : null;
  }

  /// Sottotitoli esterni in `track-list`: id e file di provenienza.
  Future<List<({String id, String filename})>> _externalSubtitles() async {
    final count =
        int.tryParse(await _native.getProperty('track-list/count')) ?? 0;
    final result = <({String id, String filename})>[];
    for (var i = 0; i < count; i++) {
      Future<String> property(String name) =>
          _native.getProperty('track-list/$i/$name');
      if (await property('type') != 'sub') continue;
      if (await property('external') != 'yes') continue;
      result.add((
        id: await property('id'),
        filename: await property('external-filename'),
      ));
    }
    return result;
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) => _native.setProperty(
      'sub-delay', (delay.inMilliseconds / 1000).toStringAsFixed(3));

  @override
  Future<void> setSubtitleScale(double scale) =>
      _native.setProperty('sub-scale', scale.toStringAsFixed(2));

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  Duration get buffer => _player.state.buffer;

  @override
  bool get playing => _player.state.playing;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<Duration> get bufferStream => _player.stream.buffer;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Widget buildView() => Video(
        controller: _video,
        controls: NoVideoControls,
        fill: Colors.black,
        // Pausa e ripresa le decide il player, non lo stato della finestra.
        pauseUponEnteringBackgroundMode: false,
        // Con libass i sottotitoli sono già disegnati nel video.
        subtitleViewConfiguration:
            const SubtitleViewConfiguration(visible: false),
      );
}
