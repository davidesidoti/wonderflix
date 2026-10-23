import 'dart:async';

import 'video_engine.dart';

/// Le aperture di un motore, una alla volta: una nuova fa fallire subito
/// quella ancora in corso, che così non libera la sorgente della nuova.
class OpenSequence {
  OpenSequence({this.timeout = const Duration(seconds: 60)});

  final Duration timeout;

  Completer<void>? _current;

  /// Carica con [attach] e aspetta [loaded]. Se fallisce (errore, timeout,
  /// [attach] che lancia) chiama [release], ma solo se nel frattempo non è
  /// partita un'altra apertura. Lancia [EngineOpenException].
  Future<void> run({
    required void Function() attach,
    required void Function() release,
  }) async {
    failed('sostituita da una nuova apertura');
    final opening = _current = Completer<void>();
    try {
      attach();
      await opening.future.timeout(timeout,
          onTimeout: () => throw const EngineOpenException('timeout'));
    } on Object {
      if (identical(_current, opening)) release();
      rethrow;
    } finally {
      if (identical(_current, opening)) _current = null;
    }
  }

  /// `true` mentre un'apertura aspetta.
  bool get pending => _current != null && !_current!.isCompleted;

  /// Il file dell'apertura in corso è caricato.
  void loaded() {
    if (pending) _current!.complete();
  }

  /// L'apertura in corso fallisce con [message].
  void failed(String message) {
    if (pending) _current!.completeError(EngineOpenException(message));
  }
}
