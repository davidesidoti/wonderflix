import 'dart:async';

/// Rilettura periodica di una scheda della pagina Amministrazione (spec J
/// §10). L'intervallo parte dalla fine della lettura precedente, quindi due
/// letture non si sovrappongono mai. Gli errori li gestisce [read]: qui si
/// ignorano, e la rilettura continua.
class AdminPoller {
  AdminPoller({required Future<void> Function() read, required Duration interval})
      : _read = read,
        _interval = interval;

  final Future<void> Function() _read;
  Duration _interval;
  Timer? _timer;

  /// L'attesa del timer in corso, `null` se non ce n'è uno.
  Duration? _pendingDelay;

  /// Le letture in corso (una, più quelle chieste nel frattempo).
  Future<void>? _running;

  /// Una lettura chiesta mentre un'altra era in corso: parte appena finisce.
  bool _again = false;
  bool _active = false;
  bool _disposed = false;

  bool get active => _active;

  Duration get interval => _interval;

  /// Vale da subito: se si sta aspettando, l'attesa riparte con il valore
  /// nuovo. La prima lettura (attesa a zero, subito dopo [start]) non si
  /// ritarda.
  set interval(Duration value) {
    if (value == _interval) return;
    _interval = value;
    if (_active && _running == null && _pendingDelay != Duration.zero) {
      _schedule(value);
    }
  }

  /// Accende la rilettura: una lettura subito, poi a ogni intervallo.
  void start() {
    if (_active || _disposed) return;
    _active = true;
    if (_running == null) _schedule(Duration.zero);
  }

  /// Spegne la rilettura; una lettura in corso finisce.
  void stop() {
    _active = false;
    _cancelTimer();
  }

  /// Una lettura adesso (dopo un'azione, "Riprova"). Se una è già in corso,
  /// ne parte un'altra appena finisce; il futuro si completa dopo quella.
  Future<void> now() {
    if (_disposed) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _run();
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  Future<void> _run() {
    _cancelTimer();
    final run = _loop();
    _running = run;
    return run;
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        try {
          // `Future.sync`: anche una lettura che lancia senza essere `async`
          // finisce nel `catch`, e [_running] non resta appeso.
          await Future.sync(_read);
        } on Object {
          // Lo stato dell'errore lo tiene chi legge.
        }
      } while (_again && !_disposed);
    } finally {
      _running = null;
      if (_active && !_disposed) _schedule(_interval);
    }
  }

  void _schedule(Duration delay) {
    _cancelTimer();
    _pendingDelay = delay;
    _timer = Timer(delay, () {
      _timer = null;
      _pendingDelay = null;
      unawaited(_run());
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _pendingDelay = null;
  }
}
