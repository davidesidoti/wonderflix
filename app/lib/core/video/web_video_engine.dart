import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

import 'hls_levels.dart';
import 'open_sequence.dart';
import 'video_engine.dart';
import 'web_subtitles.dart';

final _log = Logger('player');

/// hls.js, caricato da `web/index.html` (`web/vendor/hls.js-*`).
@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external _Hls(_HlsConfig config);

  external static bool isSupported();

  external void loadSource(String url);

  external void attachMedia(web.HTMLMediaElement media);

  external void on(String event, JSFunction callback);

  external void recoverMediaError();

  external JSArray<_HlsLevel> get levels;

  /// Impostato, toglie la scelta automatica (e vale anche come partenza).
  external set loadLevel(int index);

  external void destroy();
}

extension type _HlsConfig._(JSObject _) implements JSObject {
  external factory _HlsConfig({double startPosition, JSFunction xhrSetup});
}

extension type _HlsLevel._(JSObject _) implements JSObject {
  external String get uri;
}

extension type _HlsErrorData._(JSObject _) implements JSObject {
  external bool get fatal;

  external String get type;

  external String get details;
}

/// [VideoEngine] del browser: un `<video>`, con hls.js per l'HLS dove il
/// browser non lo legge da solo. Non sceglie le tracce interne del file:
/// il cambio di audio riapre il video dal server.
class WebVideoEngine implements VideoEngine {
  WebVideoEngine() {
    container
      ..style.position = 'relative'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.background = 'black'
      // I tocchi vanno ai controlli Flutter, non al video.
      ..style.pointerEvents = 'none'
      ..append(_video);
    _video
      ..playsInline = true
      ..preservesPitch = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.background = 'black';
    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int _) => container);
    _subscriptions.addAll([
      _video.onTimeUpdate.listen((_) => _position.add(position)),
      _video.onDurationChange.listen((_) {
        _duration.add(duration);
        _completeOpening();
      }),
      _video.onLoadedMetadata.listen((_) {
        // Con hls.js la partenza è già nella configurazione (`startPosition`).
        if (_hls == null && _start > Duration.zero) {
          _video.currentTime = _seconds(_start);
        }
        _completeOpening();
      }),
      _video.onLoadedData.listen((_) {
        if (!_firstFrame.isCompleted) _firstFrame.complete();
      }),
      web.EventStreamProviders.progressEvent
          .forElement(_video)
          .listen((_) => _buffer.add(buffer)),
      _video.onPlay.listen((_) => _playing.add(true)),
      _video.onPause.listen((_) => _playing.add(false)),
      _video.onWaiting.listen((_) => _buffering.add(true)),
      _video.onSeeking.listen((_) => _buffering.add(true)),
      _video.onPlaying.listen((_) => _buffering.add(false)),
      _video.onCanPlay.listen((_) => _buffering.add(false)),
      _video.onSeeked.listen((_) => _buffering.add(false)),
      _video.onEnded.listen((_) => _completed.add(true)),
      _video.onError.listen((_) {
        final error = _video.error;
        _fail(error == null
            ? 'errore del video'
            : 'video ${error.code}: ${error.message}');
      }),
    ]);
  }

  static int _views = 0;

  final String _viewType = 'wonderflix-video-${_views++}';

  /// Contenitore del platform view: il `<video>` e, sopra, i canvas dei
  /// sottotitoli ASS e PGS.
  final web.HTMLDivElement container = web.HTMLDivElement();

  final web.HTMLVideoElement _video = web.HTMLVideoElement();
  late final _subtitles = WebSubtitles(_video);
  final _subscriptions = <StreamSubscription<web.Event>>[];

  _Hls? _hls;
  Duration _start = Duration.zero;
  // La transcodifica sul server può impiegare parecchi secondi a partire.
  final _openings = OpenSequence();

  /// `true` dopo un `recoverMediaError` di hls.js in questa apertura.
  bool _recovered = false;
  final _firstFrame = Completer<void>();

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();

  @override
  Future<void> open(VideoSource source) async {
    _unload();
    _subtitles
      ..clear(keepDownloads: true)
      ..headers = source.headers;
    _start = source.start;
    _recovered = false;
    await _openings.run(attach: () => _attach(source), release: _unload);
  }

  void _attach(VideoSource source) {
    final url = source.url;
    // Come jellyfin-web: hls.js ovunque ci sia MSE. L'HLS nativo di Chrome
    // sceglie da solo la variante H.264 (transcodifica completa) e si blocca
    // sui salti lontani; resta solo per i browser senza MSE (Safari su iOS).
    if (url.contains('.m3u8') && _useHlsJs()) {
      // La playlist può non ricopiare il token nei segmenti: va nell'header.
      final authorization = source.headers['Authorization'];
      final hls = _hls = _Hls(_HlsConfig(
        startPosition: _seconds(source.start),
        xhrSetup: ((web.XMLHttpRequest xhr, JSString _) {
          if (authorization != null) {
            xhr.setRequestHeader('Authorization', authorization);
          }
        }).toJS,
      ));
      hls.on(
          'hlsManifestParsed',
          ((JSString _, JSObject _) {
            final levels = hls.levels.toDart;
            final index = copyLevel([for (final level in levels) level.uri]);
            if (levels.isNotEmpty) {
              _log.info('hls.js: livello $index di ${levels.length}');
              hls.loadLevel = index;
            }
          }).toJS);
      hls.on(
          'hlsError',
          ((JSString _, _HlsErrorData data) {
            final message = 'hls.js ${data.type}/${data.details}';
            if (!data.fatal) {
              _errors.add(message);
            } else if (data.type == 'mediaError' && !_recovered) {
              // Un errore di decodifica si recupera una volta, poi si rinuncia.
              _recovered = true;
              _errors.add('$message: recupero');
              hls.recoverMediaError();
            } else {
              _fail(message);
            }
          }).toJS);
      hls
        ..loadSource(url)
        ..attachMedia(_video);
    } else {
      _video.src = url;
    }
  }

  /// `false` se il browser non ha MSE, o se hls.js non si è caricato ma il
  /// browser legge l'HLS da solo; altrimenti, senza hls.js,
  /// [EngineOpenException].
  bool _useHlsJs() {
    try {
      return _Hls.isSupported();
    } on Object catch (error) {
      if (_video.canPlayType('application/vnd.apple.mpegurl').isNotEmpty) {
        _log.warning('hls.js non disponibile, HLS nativo: $error');
        return false;
      }
      throw EngineOpenException('hls.js non disponibile: $error');
    }
  }

  void _completeOpening() {
    final seconds = _video.duration;
    if (seconds.isFinite && seconds > 0) _openings.loaded();
  }

  /// Un errore durante l'apertura la fa fallire; dopo va solo nel log.
  void _fail(String message) {
    _errors.add(message);
    _openings.failed(message);
  }

  /// Libera la sorgente (e hls.js), senza togliere gli ascoltatori.
  void _unload() {
    final hls = _hls;
    _hls = null;
    hls?.destroy();
    if (_video.hasAttribute('src')) {
      _video
        ..removeAttribute('src')
        ..load();
    }
  }

  @override
  Future<void> play() async {
    try {
      await _video.play().toDart;
    } on Object catch (error) {
      // Di solito il browser vuole un gesto dell'utente prima dell'audio.
      _log.warning('play rifiutato dal browser: $error');
      _playing.add(false);
    }
  }

  @override
  Future<void> pause() async => _video.pause();

  @override
  Future<void> seek(Duration position) async =>
      _video.currentTime = _seconds(position);

  @override
  Future<void> setVolume(double volume) async =>
      _video.volume = (volume / 100).clamp(0, 1);

  @override
  Future<void> setRate(double rate) async => _video
    ..playbackRate = rate
    ..preservesPitch = true;

  @override
  bool get selectsEmbeddedTracks => false;

  @override
  Future<List<EngineTrack>> tracks() async => const [];

  @override
  Future<void> selectAudio(String? id) async {}

  @override
  Future<void> selectSubtitle(String? id) => _subtitles.select(id);

  @override
  Future<String?> addSubtitle(
    String url, {
    String? title,
    String? language,
  }) =>
      _subtitles.add(url);

  @override
  Future<void> setSubtitleDelay(Duration delay) async =>
      _subtitles.setDelay(delay);

  @override
  Future<void> setSubtitleScale(double scale) async =>
      _subtitles.setScale(scale);

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _openings.failed('motore chiuso');
    _subtitles.clear();
    _unload();
  }

  @override
  Duration get position => _fromSeconds(_video.currentTime);

  @override
  Duration get duration => _fromSeconds(_video.duration);

  @override
  Duration get buffer {
    final time = _video.currentTime;
    final ranges = _video.buffered;
    for (var i = 0; i < ranges.length; i++) {
      if (ranges.start(i) <= time && time <= ranges.end(i)) {
        return _fromSeconds(ranges.end(i));
      }
    }
    return position;
  }

  @override
  bool get playing => !_video.paused;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<Duration> get bufferStream => _buffer.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Future<void> get firstFrame => _firstFrame.future;

  // Il platform view, colpito, vince l'arena dei gesti: il tocco sul film
  // non arriverebbe al `GestureDetector` del player. Il video non ne vuole.
  @override
  Widget buildView() => IgnorePointer(
        child: Stack(fit: StackFit.expand, children: [
          HtmlElementView(viewType: _viewType),
          _subtitles.view(),
        ]),
      );
}

double _seconds(Duration value) => value.inMicroseconds / 1e6;

/// Secondi del `<video>` (anche `NaN` o infiniti) come [Duration].
Duration _fromSeconds(double seconds) => seconds.isFinite && seconds > 0
    ? Duration(microseconds: (seconds * 1e6).round())
    : Duration.zero;
