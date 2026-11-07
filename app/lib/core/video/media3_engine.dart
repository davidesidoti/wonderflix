import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'video_engine.dart';

final _log = Logger('player');

/// Un solo flusso nativo per tutti i player: un secondo `listen` sullo stesso
/// EventChannel sostituirebbe il primo e due motori vivi (passaggio al
/// prossimo episodio) perderebbero gli eventi. Ogni motore filtra per `id`.
final Stream<dynamic> _playerEvents = const EventChannel(
  'wonderflix/player/events',
).receiveBroadcastStream();

/// Traduce il `Format.id` di Media3 in indice ffprobe e provenienza.
/// `"3"` e `"0:3"` (periodo 0 = il file) sono lo stream 2 del file (TrackNumber
/// di Matroska = indice + 1); con periodo > 0 la traccia è di un file esterno.
({int? ffIndex, bool external}) parseFormatId(String? formatId) {
  final parts = (formatId ?? '').split(':');
  final id = int.tryParse(parts.last);
  if (parts.length == 2) {
    final period = int.tryParse(parts.first);
    if (period == null) return (ffIndex: null, external: false);
    if (period > 0) return (ffIndex: null, external: true);
  } else if (parts.length != 1) {
    return (ffIndex: null, external: false);
  }
  return (ffIndex: id != null && id >= 1 ? id - 1 : null, external: false);
}

/// [VideoEngine] sopra Media3/ExoPlayer (Android TV), dietro il canale
/// `wonderflix/player`. Il lato nativo è un player per `id`; il video è una
/// platform view.
class Media3Engine implements VideoEngine {
  Media3Engine({
    MethodChannel channel = const MethodChannel('wonderflix/player'),
    Stream<dynamic>? events,
  }) : _channel = channel,
       _events = events ?? _playerEvents;

  /// La transcodifica sul server può impiegare parecchi secondi a partire.
  static const openTimeout = Duration(seconds: 60);

  final MethodChannel _channel;
  final Stream<dynamic> _events;

  /// Creato alla prima chiamata: il costruttore non tocca il canale.
  Future<int>? _idFuture;
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;

  Completer<void>? _loading;
  final _firstFrame = Completer<void>();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _playing = false;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Future<int> _ensureId() => _idFuture ??= () async {
    final id = await _channel.invokeMethod<int>('create');
    if (id == null) throw StateError('create senza id');
    _subscription = _events.listen((event) => _onEvent(id, event));
    return id;
  }();

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    final id = await _ensureId();
    return _channel.invokeMethod<T>(method, {'id': id, ...?arguments});
  }

  void _onEvent(int id, dynamic event) {
    if (_disposed || event is! Map || event['id'] != id) return;
    final value = event['value'];
    Duration ms() => Duration(milliseconds: (value as num).toInt());
    switch (event['type']) {
      case 'loaded':
        final loading = _loading;
        if (loading != null && !loading.isCompleted) loading.complete();
      case 'error':
        final loading = _loading;
        if (loading != null && !loading.isCompleted) {
          loading.completeError(EngineOpenException('$value'));
        } else {
          _errorController.add('$value');
        }
      case 'position':
        _positionController.add(_position = ms());
      case 'duration':
        _durationController.add(_duration = ms());
      case 'buffer':
        _bufferController.add(_buffer = ms());
      case 'playing':
        _playingController.add(_playing = value as bool);
      case 'buffering':
        _bufferingController.add(value as bool);
      case 'completed':
        _completedController.add(value as bool);
      case 'firstFrame':
        if (!_firstFrame.isCompleted) _firstFrame.complete();
    }
  }

  @override
  Future<void> open(VideoSource source) async {
    final id = await _ensureId();
    if (_disposed) throw const EngineOpenException('disposed');
    // Azzera lo stato del file precedente (durata compresa) prima di aprire.
    _position = _duration = _buffer = Duration.zero;
    final loading = _loading = Completer<void>();
    // L'eventuale errore viene letto più sotto: evita che risulti "non gestito".
    loading.future.ignore();
    try {
      await _channel.invokeMethod<void>('open', {
        'id': id,
        'url': source.url,
        'headers': source.headers,
        'startMs': source.start.inMilliseconds,
      });
      await loading.future.timeout(
        openTimeout,
        onTimeout: () => throw const EngineOpenException('timeout'),
      );
    } on Object {
      // Dopo un errore il file non deve restare caricato (né scaricare dati).
      if (!_disposed) {
        try {
          await _channel.invokeMethod<void>('stop', {'id': id});
        } on Object catch (error) {
          _log.warning('stop dopo apertura non riuscita: $error');
        }
      }
      rethrow;
    } finally {
      if (_loading == loading) _loading = null;
    }
  }

  @override
  Future<void> play() => _call<void>('play');

  @override
  Future<void> pause() => _call<void>('pause');

  @override
  Future<void> seek(Duration position) =>
      _call<void>('seek', {'ms': position.inMilliseconds});

  @override
  Future<void> setVolume(double volume) =>
      _call<void>('setVolume', {'volume': volume / 100});

  @override
  Future<void> setRate(double rate) => _call<void>('setRate', {'rate': rate});

  @override
  bool get selectsEmbeddedTracks => true;

  @override
  Future<List<EngineTrack>> tracks() async {
    final list = await _call<List<Object?>>('tracks') ?? const [];
    final tracks = <EngineTrack>[];
    for (final item in list.cast<Map<Object?, Object?>>()) {
      final type = switch (item['type']) {
        'video' => EngineTrackType.video,
        'audio' => EngineTrackType.audio,
        'subtitle' => EngineTrackType.subtitle,
        _ => null,
      };
      if (type == null) continue;
      final format = parseFormatId(item['formatId'] as String?);
      tracks.add(
        EngineTrack(
          id: item['id']! as String,
          type: type,
          ffIndex: format.ffIndex,
          external: format.external,
          title: item['title'] as String?,
          language: item['language'] as String?,
        ),
      );
    }
    return tracks;
  }

  @override
  Future<void> selectAudio(String? id) =>
      _call<void>('selectAudio', {'track': id});

  @override
  Future<void> selectSubtitle(String? id) =>
      _call<void>('selectSubtitle', {'track': id});

  @override
  Future<String?> addSubtitle(String url, {String? title, String? language}) =>
      _call<String>('addSubtitle', {
        'url': url,
        'title': title,
        'language': language,
      });

  @override
  Future<void> setSubtitleDelay(Duration delay) =>
      _call<void>('setSubtitleDelay', {'ms': delay.inMilliseconds});

  @override
  Future<void> setSubtitleScale(double scale) =>
      _call<void>('setSubtitleScale', {'scale': scale});

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final loading = _loading;
    if (loading != null && !loading.isCompleted) {
      loading.completeError(const EngineOpenException('disposed'));
    }
    await _subscription?.cancel();
    final idFuture = _idFuture;
    if (idFuture != null) {
      await _channel.invokeMethod<void>('dispose', {'id': await idFuture});
    }
    for (final controller in [
      _positionController,
      _durationController,
      _bufferController,
      _playingController,
      _bufferingController,
      _completedController,
      _errorController,
    ]) {
      await controller.close();
    }
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
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<Duration> get bufferStream => _bufferController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<void> get playBlockedStream => const Stream.empty();

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  Future<void> get firstFrame => _firstFrame.future;

  @override
  Widget buildView() => FutureBuilder<int>(
    future: _ensureId(),
    builder: (context, snapshot) {
      final id = snapshot.data;
      if (id == null) return const ColoredBox(color: Colors.black);
      const viewType = 'wonderflix/player_view';
      // Hybrid Composition: la SurfaceView di Media3 non regge il Virtual
      // Display.
      return PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (params) =>
            PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: viewType,
                layoutDirection: TextDirection.ltr,
                creationParams: {'id': id},
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..create(),
      );
    },
  );
}
