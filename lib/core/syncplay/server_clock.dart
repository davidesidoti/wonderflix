import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';

final _log = Logger('watchparty');

/// Una misura dell'orologio del server, con il metodo di NTP.
class ClockSample {
  factory ClockSample({
    required DateTime sent,
    required DateTime serverReceived,
    required DateTime serverSent,
    required DateTime received,
  }) {
    final offset = Duration(
        microseconds: (serverReceived.difference(sent).inMicroseconds +
                serverSent.difference(received).inMicroseconds) ~/
            2);
    final delay =
        received.difference(sent) - serverSent.difference(serverReceived);
    return ClockSample._(offset, delay);
  }

  const ClockSample._(this.offset, this.delay);

  /// Orario del server − orario locale.
  final Duration offset;

  /// Andata e ritorno in rete, senza il tempo passato sul server.
  final Duration delay;

  Duration get ping => Duration(microseconds: delay.inMicroseconds ~/ 2);
}

/// Chiede al server i suoi due istanti (`/GetUtcTime`).
typedef ServerTimeFetcher = Future<({DateTime serverReceived, DateTime serverSent})>
    Function();

/// Stima dell'orologio del server, per eseguire i comandi del gruppo
/// all'istante giusto. Usa solo `clock.now()`: nei test il tempo è finto.
class ServerClock {
  ServerClock({required ServerTimeFetcher fetch, void Function(Duration)? onPing})
      : _fetch = fetch,
        _onPing = onPing;

  static const greedyInterval = Duration(seconds: 1);
  static const greedyCount = 3;
  static const slowInterval = Duration(seconds: 60);
  static const maxSamples = 8;

  final ServerTimeFetcher _fetch;

  /// Chiamato dopo ogni misura riuscita con il ping della misura migliore
  /// (il gruppo lo manda al server con `/SyncPlay/Ping`).
  final void Function(Duration ping)? _onPing;

  final _samples = <ClockSample>[];
  final _first = Completer<void>();
  ClockSample? _best;
  Timer? _timer;
  bool _running = false;
  int _taken = 0;

  /// `true` dopo la prima misura riuscita.
  bool get ready => _best != null;

  /// Si completa alla prima misura riuscita.
  Future<void> get firstSample => _first.future;

  Duration get offset => _best?.offset ?? Duration.zero;

  Duration get ping => _best?.ping ?? Duration.zero;

  /// Ora locale (UTC).
  DateTime now() => clock.now().toUtc();

  DateTime serverNow() => toServer(clock.now());

  DateTime toServer(DateTime local) => local.toUtc().add(offset);

  DateTime toLocal(DateTime server) => server.toUtc().subtract(offset);

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_measure());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _measure() async {
    if (!_running) return;
    final sent = clock.now().toUtc();
    try {
      final (:serverReceived, :serverSent) = await _fetch();
      final received = clock.now().toUtc();
      if (!_running) return;
      _add(ClockSample(
        sent: sent,
        serverReceived: serverReceived,
        serverSent: serverSent,
        received: received,
      ));
      _onPing?.call(ping);
    } on Object catch (error) {
      _log.info('misura dell\'orologio del server non riuscita: $error');
    }
    if (!_running) return;
    _taken++;
    _timer = Timer(_taken < greedyCount ? greedyInterval : slowInterval,
        () => unawaited(_measure()));
  }

  void _add(ClockSample sample) {
    _samples.add(sample);
    if (_samples.length > maxSamples) _samples.removeAt(0);
    _best = _samples.reduce((a, b) => b.delay < a.delay ? b : a);
    if (!_first.isCompleted) _first.complete();
    _log.fine('orologio: offset ${offset.inMilliseconds} ms, '
        'ping ${ping.inMilliseconds} ms');
  }
}
