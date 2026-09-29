import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/jellyfin/playback_api.dart';
import '../../core/jellyfin/playback_models.dart';

/// Invia a Jellyfin l'inizio, l'avanzamento (ogni [interval] e a ogni
/// evento) e la fine della riproduzione. Gli errori di rete vengono solo
/// scritti nel log: la riproduzione non si interrompe. In caso di crash si
/// perdono al massimo [interval] di avanzamento.
class ProgressReporter {
  ProgressReporter({
    required PlaybackApi api,
    required PlaybackReport Function() snapshot,
    this.interval = const Duration(seconds: 10),
    this.stopTimeout = const Duration(seconds: 2),
  })  : _api = api,
        _snapshot = snapshot;

  final PlaybackApi _api;

  /// Stato corrente della riproduzione, letto al momento di ogni invio.
  final PlaybackReport Function() _snapshot;
  final Duration interval;

  /// Attesa massima del report di fine (es. alla chiusura della finestra).
  final Duration stopTimeout;

  Timer? _timer;
  bool _started = false;
  bool _stopped = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(interval, (_) => onEvent());
    await _send(() => _api.reportStart(_snapshot()));
  }

  /// Avanzamento immediato: pausa, ripresa, salto, cambio traccia.
  void onEvent() {
    if (!_started || _stopped) return;
    unawaited(_send(() => _api.reportProgress(_snapshot())));
  }

  /// Fine della riproduzione. Si può chiamare più volte: invia una volta sola.
  Future<void> stop() async {
    if (!_started || _stopped) return;
    _stopped = true;
    _timer?.cancel();
    final report = _snapshot();
    await _send(() => _api.reportStopped(report))
        .timeout(stopTimeout, onTimeout: () {});
  }

  Future<void> _send(Future<void> Function() request) async {
    try {
      await request();
    } on Object catch (error) {
      debugPrint('[player] report non inviato: $error');
    }
  }
}
