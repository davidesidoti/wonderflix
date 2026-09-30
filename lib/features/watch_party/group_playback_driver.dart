import 'dart:async';

import 'package:logging/logging.dart';

import '../../core/syncplay/drift_corrector.dart';
import '../../core/syncplay/server_clock.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../core/video/video_engine.dart';

final _log = Logger('watchparty');

/// Collega il player aperto al gruppo (spec B §4.5–4.6):
/// - esegue i comandi del gruppo all'istante giusto;
/// - manda `Ready` a file aperto e dopo i salti, `Buffering` se il buffering
///   dura più di 1 s con il gruppo in riproduzione;
/// - durante la visione corregge lo scarto con la velocità
///   ([DriftCorrector]), con un salto solo se è troppo grande.
class GroupPlaybackDriver {
  GroupPlaybackDriver({
    required VideoEngine engine,
    required SyncPlayApi api,
    required ServerClock clock,
    required this.playlistItemId,
    required Stream<SyncPlayCommand> commands,
    SyncPlayCommand? lastCommand,
  })  : _engine = engine,
        _api = api,
        _clock = clock,
        _commandStream = commands,
        _pending = lastCommand;

  /// Sotto questo scarto, a video fermo, non si salta.
  static const alignTolerance = Duration(milliseconds: 40);

  /// Attesa massima della prima misura dell'orologio prima del `Ready`.
  static const clockWait = Duration(seconds: 3);

  /// Buffering più breve di così: il gruppo non lo sa.
  static const bufferingThreshold = Duration(seconds: 1);

  /// Ogni quanto si misura lo scarto.
  static const tick = Duration(milliseconds: 500);

  /// Dopo un `Seek`, il salto è arrivato quando la posizione del motore è
  /// così vicina alla destinazione (con mpv arriva dopo `seek()`).
  static const seekLanding = Duration(milliseconds: 250);

  /// Attesa massima della nuova posizione dopo un `Seek`.
  static const seekTimeout = Duration(seconds: 3);

  /// Quante volte si riapplica un comando doppio con lo stato incoerente.
  static const maxReapply = 2;

  final VideoEngine _engine;
  final SyncPlayApi _api;
  final ServerClock _clock;
  final Stream<SyncPlayCommand> _commandStream;

  /// Elemento della coda aperto in questo player.
  final String playlistItemId;

  final _subscriptions = <StreamSubscription<Object?>>[];

  final _corrector = DriftCorrector();
  Timer? _bufferingTimer;
  Timer? _ticker;
  bool _reportedBuffering = false;
  double _rate = 1.0;

  /// Da quando il video va dopo l'ultimo `Unpause` (per il periodo iniziale).
  DateTime? _playingSince;
  DateTime? _lastResync;

  /// Ultimo comando arrivato prima dell'apertura del file.
  SyncPlayCommand? _pending;

  /// Ultimo comando applicato.
  SyncPlayCommand? _current;
  Timer? _scheduled;
  bool _loaded = false;
  bool _buffering = false;
  bool _readyPending = false;
  bool _disposed = false;

  /// Volte in cui l'ultimo comando è stato riapplicato (§4.5, doppioni).
  int _reapplied = 0;

  /// Fine dell'attesa della posizione dopo un `Seek`, se in corso.
  Completer<void>? _landing;

  void start() {
    _subscriptions.addAll([
      _commandStream.listen(_receive),
      _engine.bufferingStream.listen(_onBuffering),
    ]);
    _ticker = Timer.periodic(tick, (_) => _onTick());
  }

  /// Il file è aperto, in pausa sulla posizione di partenza (anche dopo un
  /// "Riprova" o il ripiego sulla transcodifica): il gruppo può partire.
  Future<void> onLoaded() async {
    if (_disposed) return;
    _loaded = true;
    if (!_clock.ready) {
      await _clock.firstSample.timeout(clockWait, onTimeout: () {});
      if (_disposed) return;
    }
    await _sendReady();
    final pending = _pending;
    _pending = null;
    if (pending != null) _receive(pending);
  }

  /// Il file non è più pronto (errore, "Riprova", ripiego sulla
  /// transcodifica): fino al prossimo [onLoaded] i comandi aspettano.
  void onUnloaded() {
    _loaded = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopLanding();
    _scheduled?.cancel();
    _bufferingTimer?.cancel();
    _ticker?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_rate != 1.0) {
      _rate = 1.0;
      try {
        await _engine.setRate(1.0);
      } on Object catch (error) {
        // Il motore può essere già chiuso insieme al player.
        _log.info('velocità non ripristinata: $error');
      }
    }
  }

  void _receive(SyncPlayCommand command) {
    if (_disposed) return;
    if (command.type != SyncPlayCommandType.stop &&
        command.playlistItemId != playlistItemId) {
      return;
    }
    if (!_loaded) {
      _pending = command;
      return;
    }
    final current = _current;
    if (current != null && current.sameAs(command)) {
      unawaited(_recheck(command));
      return;
    }
    _current = command;
    _reapplied = 0;
    unawaited(_apply(command));
  }

  /// Il comando non è più quello da eseguire (ne è arrivato un altro, o il
  /// driver è chiuso): chi lo stava applicando si ferma.
  bool _stale(SyncPlayCommand command) =>
      _disposed || !identical(_current, command);

  Future<void> _apply(SyncPlayCommand command) async {
    _scheduled?.cancel();
    _scheduled = null;
    _stopLanding();
    _corrector.reset();
    _playingSince = null;
    await _setRate(1.0);
    if (_stale(command)) return;
    final wait = _clock.toLocal(command.when).difference(_clock.now());
    _log.info('comando ${command.type.name} a ${command.position} '
        '(tra ${wait.inMilliseconds} ms)');
    switch (command.type) {
      case SyncPlayCommandType.unpause:
        if (wait > Duration.zero) {
          if (!_engine.playing) await _align(command.position);
          if (_stale(command)) return;
          _scheduled = Timer(wait, () => unawaited(_play(command)));
        } else {
          if (!_engine.playing) await _align(_expectedPosition(command));
          await _play(command);
        }
      case SyncPlayCommandType.pause:
        if (wait > Duration.zero) {
          _scheduled = Timer(wait, () => unawaited(_pauseAt(command)));
        } else {
          await _pauseAt(command);
        }
      case SyncPlayCommandType.seek:
        await _engine.pause();
        if (_stale(command)) return;
        await _engine.seek(command.position);
        if (_stale(command)) return;
        await _waitForPosition(command.position);
        if (_stale(command)) return;
        _readyPending = true;
        if (!_buffering) await _sendReady();
      case SyncPlayCommandType.stop:
        await _engine.pause();
    }
  }

  /// Con mpv la posizione cambia dopo `seek()`: si aspetta che arrivi (al
  /// massimo [seekTimeout]) prima di mandare `Ready`.
  Future<void> _waitForPosition(Duration target) {
    bool landed(Duration position) => (position - target).abs() <= seekLanding;
    if (landed(_engine.position)) return Future.value();
    final landing = Completer<void>();
    _landing = landing;
    final timer = Timer(seekTimeout, () {
      _log.info('posizione dopo il salto non arrivata in '
          '${seekTimeout.inSeconds} s');
      if (!landing.isCompleted) landing.complete();
    });
    final subscription = _engine.positionStream.listen((position) {
      if (landed(position) && !landing.isCompleted) landing.complete();
    });
    return landing.future.whenComplete(() {
      timer.cancel();
      unawaited(subscription.cancel());
      if (identical(_landing, landing)) _landing = null;
    });
  }

  void _stopLanding() {
    final landing = _landing;
    _landing = null;
    if (landing != null && !landing.isCompleted) landing.complete();
  }

  /// Comando già ricevuto: si riapplica solo se lo stato non è coerente.
  Future<void> _recheck(SyncPlayCommand command) async {
    if (_clock.toLocal(command.when).isAfter(_clock.now())) return;
    final off = (_engine.position - command.position).abs() > alignTolerance;
    final stale = switch (command.type) {
      SyncPlayCommandType.unpause => !_engine.playing,
      SyncPlayCommandType.pause ||
      SyncPlayCommandType.seek =>
        _engine.playing || off,
      SyncPlayCommandType.stop => _engine.playing,
    };
    if (stale && _reapplied >= maxReapply) {
      // Riapplicarlo non è servito: il gruppo sa dove siamo davvero.
      _log.info('comando ${command.type.name} già riapplicato '
          '$_reapplied volte: solo Ready');
      await _sendReady();
    } else if (stale) {
      _reapplied++;
      _current = command;
      await _apply(command);
    } else if (command.type == SyncPlayCommandType.seek) {
      await _sendReady();
    }
  }

  /// Posizione del gruppo adesso, per un comando `Unpause`.
  Duration _expectedPosition(SyncPlayCommand command) {
    final elapsed = _clock.serverNow().difference(command.when);
    return elapsed.isNegative ? command.position : command.position + elapsed;
  }

  Future<void> _play(SyncPlayCommand command) async {
    if (_stale(command)) return;
    await _engine.play();
    if (_stale(command)) return;
    _playingSince = _clock.now();
    // Buffering iniziato a gruppo fermo (non segnalato): il conteggio di
    // 1 s riparte adesso che il gruppo va.
    if (_buffering) {
      _bufferingTimer ??= Timer(bufferingThreshold, _reportBuffering);
    }
  }

  Future<void> _pauseAt(SyncPlayCommand command) async {
    if (_stale(command)) return;
    await _engine.pause();
    if (_stale(command)) return;
    await _align(command.position);
  }

  /// Allineamento esatto: a video fermo il salto non si vede.
  Future<void> _align(Duration target) async {
    if ((_engine.position - target).abs() > alignTolerance) {
      await _engine.seek(target);
    }
  }

  void _onBuffering(bool buffering) {
    if (_disposed) return;
    _buffering = buffering;
    if (buffering) {
      _bufferingTimer ??= Timer(bufferingThreshold, _reportBuffering);
      return;
    }
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    if (_reportedBuffering || _readyPending) {
      final reported = _reportedBuffering;
      _reportedBuffering = false;
      final state = _snapshot();
      if (reported && state.isPlaying) _reanchor(state);
      unawaited(_sendReady(state));
    }
  }

  /// Dopo il nostro buffering il server fa ripartire il gruppo dalla
  /// posizione del nostro `Ready` (e a noi, se siamo indietro, non manda
  /// nessun comando): la linea del tempo del gruppo diventa quella.
  void _reanchor(ClientPlaybackState state) {
    final previous = _current;
    if (previous == null || previous.type != SyncPlayCommandType.unpause) {
      return;
    }
    _current = SyncPlayCommand(
      groupId: previous.groupId,
      playlistItemId: previous.playlistItemId,
      when: state.when,
      position: state.position,
      type: SyncPlayCommandType.unpause,
      emittedAt: state.when,
    );
    _corrector.reset();
    _playingSince = _clock.now();
  }

  void _reportBuffering() {
    _bufferingTimer = null;
    if (_disposed ||
        !_buffering ||
        _current?.type != SyncPlayCommandType.unpause) {
      return;
    }
    _reportedBuffering = true;
    _log.info('buffering da oltre ${bufferingThreshold.inSeconds} s: '
        'il gruppo aspetta');
    unawaited(_send('buffering', () => _api.buffering(_snapshot())));
  }

  void _onTick() {
    final command = _current;
    final since = _playingSince;
    if (_disposed ||
        command == null ||
        since == null ||
        command.type != SyncPlayCommandType.unpause ||
        !_engine.playing ||
        _buffering) {
      return;
    }
    final expected = _expectedPosition(command);
    final now = _clock.now();
    final lastResync = _lastResync;
    final action = _corrector.update(
      drift: expected - _engine.position,
      rate: _rate,
      sinceUnpause: now.difference(since),
      sinceResync: lastResync == null ? null : now.difference(lastResync),
    );
    switch (action) {
      case KeepRate():
        break;
      case ChangeRate(:final rate):
        _log.info('scarto ${_corrector.lastDrift?.inMilliseconds} ms: '
            'velocità $rate');
        unawaited(_setRate(rate));
      case Resync():
        _lastResync = now;
        _log.info('scarto oltre ${DriftCorrector.resyncThreshold.inSeconds} s: '
            'riallineamento a $expected');
        unawaited(_engine.seek(expected));
    }
  }

  Future<void> _setRate(double rate) async {
    if (_rate == rate) return;
    _rate = rate;
    try {
      await _engine.setRate(rate);
    } on Object catch (error) {
      _log.warning('velocità non impostata: $error');
    }
  }

  ClientPlaybackState _snapshot() => ClientPlaybackState(
        when: _clock.serverNow(),
        position: _engine.position,
        isPlaying: _engine.playing,
        playlistItemId: playlistItemId,
      );

  Future<void> _sendReady([ClientPlaybackState? state]) async {
    _readyPending = false;
    final snapshot = state ?? _snapshot();
    await _send('ready', () => _api.ready(snapshot));
  }

  Future<void> _send(String what, Future<void> Function() request) async {
    try {
      await request();
    } on Object catch (error) {
      _log.warning('$what non inviato al gruppo: $error');
    }
  }
}
