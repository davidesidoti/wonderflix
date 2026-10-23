import 'dart:async';

import 'package:flutter/widgets.dart';

import 'video_engine.dart';

VideoEngine createVideoEngine({required bool hardwareDecoding}) =>
    _PendingWebEngine();

/// Provvisorio: il player web arriva con `WebVideoEngine` (piano 27, Task 7).
/// Per ora ogni apertura fallisce e il player mostra il suo errore.
class _PendingWebEngine implements VideoEngine {
  @override
  Future<void> open(VideoSource source) async =>
      throw const EngineOpenException('player web non ancora pronto');

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<List<EngineTrack>> tracks() async => const [];

  @override
  Future<void> selectAudio(String? id) async {}

  @override
  Future<void> selectSubtitle(String? id) async {}

  @override
  Future<String?> addSubtitle(
    String url, {
    String? title,
    String? language,
  }) async => null;

  @override
  Future<void> setSubtitleDelay(Duration delay) async {}

  @override
  Future<void> setSubtitleScale(double scale) async {}

  @override
  Future<void> dispose() async {}

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  Duration get buffer => Duration.zero;

  @override
  bool get playing => false;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration> get durationStream => const Stream.empty();

  @override
  Stream<Duration> get bufferStream => const Stream.empty();

  @override
  Stream<bool> get playingStream => const Stream.empty();

  @override
  Stream<bool> get bufferingStream => const Stream.empty();

  @override
  Stream<bool> get completedStream => const Stream.empty();

  @override
  Stream<String> get errorStream => const Stream.empty();

  // Mai completato: non si disegna nessun fotogramma.
  @override
  Future<void> get firstFrame => Completer<void>().future;

  @override
  Widget buildView() => const SizedBox.shrink();
}
