import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/server_clock.dart';
import 'package:wonderflix/core/syncplay/start_lag.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/watch_party/group_playback_driver.dart';

import '../../support/playback_fakes.dart';
import '../../support/watch_party_fakes.dart';

/// Esclusione dall'attesa come nella sessione: la richiesta parte solo
/// quando cambia.
class _WaitExclusion implements WaitExclusion {
  _WaitExclusion(this.api);

  final FakeSyncPlayApi api;
  bool ignoring = false;

  @override
  Future<void> ignoreWait() async {
    if (ignoring) return;
    ignoring = true;
    await api.setIgnoreWait(true);
  }

  @override
  Future<void> stopIgnoringWait() async {
    if (!ignoring) return;
    ignoring = false;
    await api.setIgnoreWait(false);
  }
}

void main() {
  late FakeVideoEngine engine;
  late FakeSyncPlayApi api;
  late ServerClock serverClock;
  late StreamController<SyncPlayCommand> commands;
  late GroupPlaybackDriver driver;
  late _WaitExclusion waitExclusion;

  /// Riallineamenti segnalati dal driver (`onResync`).
  var resyncs = 0;

  /// Ultimo scarto segnalato dal driver (`onDrift`).
  Duration? lastDrift;

  /// Tutto dentro la zona finta: file aperto a 10:00, orologio pronto
  /// (scarto zero). Con [load] il file è già caricato e il `Ready` iniziale
  /// è già partito (le chiamate vengono azzerate).
  void setUpDriver(FakeAsync async,
      {bool load = true, StartLag? startLag, bool ignoringWait = false}) {
    engine = FakeVideoEngine();
    unawaited(engine
        .open(const VideoSource(url: 'x', start: Duration(minutes: 10))));
    api = FakeSyncPlayApi();
    waitExclusion = _WaitExclusion(api)..ignoring = ignoringWait;
    serverClock = ServerClock(fetch: () async {
      final now = clock.now().toUtc();
      return (serverReceived: now, serverSent: now);
    })
      ..start();
    commands = StreamController<SyncPlayCommand>.broadcast();
    resyncs = 0;
    lastDrift = null;
    driver = GroupPlaybackDriver(
      engine: engine,
      api: api,
      clock: serverClock,
      playlistItemId: 'p1',
      commands: commands.stream,
      onResync: () => resyncs++,
      onDrift: (drift) => lastDrift = drift,
      startLag: startLag,
      waitExclusion: waitExclusion,
    )..start();
    async.flushMicrotasks();
    if (load) {
      unawaited(driver.onLoaded());
      async.flushMicrotasks();
    }
    engine.calls.clear();
    api.calls.clear();
  }

  void tearDownDriver(FakeAsync async) {
    unawaited(driver.dispose());
    serverClock.stop();
    unawaited(commands.close());
    async.flushMicrotasks();
  }

  /// Comando da eseguire tra [at] (negativo = già passato).
  SyncPlayCommand command(SyncPlayCommandType type,
      {Duration position = const Duration(minutes: 10),
      Duration at = Duration.zero,
      String item = 'p1'}) {
    final when = clock.now().toUtc().add(at);
    return SyncPlayCommand(
      groupId: 'g1',
      playlistItemId: item,
      when: when,
      position: position,
      type: type,
      emittedAt: when,
    );
  }

  void send(FakeAsync async, SyncPlayCommand command) {
    commands.add(command);
    async.flushMicrotasks();
  }

  /// Fa scorrere [duration] con il video in ritardo di [lag] rispetto al
  /// gruppo, partito con [from]. La posizione viene impostata prima di ogni
  /// passo, così al controllo (ogni 500 ms) è esatta.
  void runPlayback(FakeAsync async, Duration duration,
      {required SyncPlayCommand from, Duration lag = Duration.zero}) {
    const step = Duration(milliseconds: 100);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
      final next = clock.now().toUtc().add(step);
      engine.emitPosition(from.position + next.difference(from.when) - lag);
      async.elapse(step);
    }
  }

  /// Come mpv: il video parte [startLag] dopo l'istante del comando [from],
  /// dalla posizione su cui era fermo.
  void runLaggedStart(FakeAsync async, Duration duration,
      {required SyncPlayCommand from, required Duration startLag}) {
    final origin = engine.position;
    const step = Duration(milliseconds: 100);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
      final next = clock.now().toUtc().add(step);
      final running = next.difference(from.when) - startLag;
      engine.emitPosition(
          origin + (running.isNegative ? Duration.zero : running));
      async.elapse(step);
    }
  }

  test('a file aperto manda Ready, in pausa sulla posizione di partenza', () {
    fakeAsync((async) {
      setUpDriver(async, load: false);
      unawaited(driver.onLoaded());
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      final ready = api.readyStates.single;
      expect(ready.position, const Duration(minutes: 10));
      expect(ready.isPlaying, isFalse);
      expect(ready.playlistItemId, 'p1');
      tearDownDriver(async);
    });
  });

  test('comando arrivato prima dell\'apertura: applicato dopo il Ready', () {
    fakeAsync((async) {
      setUpDriver(async, load: false);
      send(async,
          command(SyncPlayCommandType.pause, position: const Duration(minutes: 12)));
      expect(engine.calls, isEmpty);
      unawaited(driver.onLoaded());
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      expect(engine.calls, ['pause']);
      expect(engine.seeks, [const Duration(minutes: 12)]);
      tearDownDriver(async);
    });
  });

  test('Unpause futuro: allinea da fermo e parte all\'istante previsto', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(
          async,
          command(SyncPlayCommandType.unpause,
              position: const Duration(minutes: 11),
              at: const Duration(milliseconds: 500)));
      expect(engine.seeks, [const Duration(minutes: 11)]);
      expect(engine.calls, isNot(contains('play')));
      async.elapse(const Duration(milliseconds: 499));
      expect(engine.calls, isNot(contains('play')));
      async.elapse(const Duration(milliseconds: 1));
      expect(engine.calls, ['play']);
      tearDownDriver(async);
    });
  });

  test('Unpause futuro con la posizione già giusta: nessun salto', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(
          async,
          command(SyncPlayCommandType.unpause,
              position: const Duration(minutes: 10, milliseconds: 30),
              at: const Duration(milliseconds: 200)));
      async.elapse(const Duration(milliseconds: 200));
      expect(engine.seeks, isEmpty);
      expect(engine.calls, ['play']);
      tearDownDriver(async);
    });
  });

  test('Unpause già passato: salta alla posizione stimata e parte', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async,
          command(SyncPlayCommandType.unpause, at: const Duration(seconds: -2)));
      expect(engine.seeks, [const Duration(minutes: 10, seconds: 2)]);
      expect(engine.calls, ['play']);
      tearDownDriver(async);
    });
  });

  test('Pause: ferma e si allinea alla posizione del gruppo', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async, command(SyncPlayCommandType.unpause));
      engine.calls.clear();
      send(async,
          command(SyncPlayCommandType.pause, position: const Duration(minutes: 12)));
      expect(engine.calls, ['pause']);
      expect(engine.seeks, [const Duration(minutes: 12)]);
      tearDownDriver(async);
    });
  });

  test('Pause futura: ferma all\'istante previsto', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async, command(SyncPlayCommandType.unpause));
      engine.calls.clear();
      send(
          async,
          command(SyncPlayCommandType.pause,
              at: const Duration(milliseconds: 300)));
      expect(engine.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.calls, ['pause']);
      tearDownDriver(async);
    });
  });

  test('Seek: pausa, salto e Ready', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async,
          command(SyncPlayCommandType.seek, position: const Duration(minutes: 20)));
      expect(engine.calls, ['pause']);
      expect(engine.seeks, [const Duration(minutes: 20)]);
      expect(api.calls, ['ready']);
      expect(api.readyStates.last.position, const Duration(minutes: 20));
      expect(api.readyStates.last.isPlaying, isFalse);
      tearDownDriver(async);
    });
  });

  test('Seek con mpv: Ready solo quando la nuova posizione è arrivata', () {
    fakeAsync((async) {
      setUpDriver(async);
      engine.seekDelay = const Duration(milliseconds: 200);
      send(async,
          command(SyncPlayCommandType.seek, position: const Duration(minutes: 20)));
      expect(engine.seeks, [const Duration(minutes: 20)]);
      async.elapse(const Duration(milliseconds: 199));
      expect(api.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(api.calls, ['ready']);
      expect(api.readyStates.last.position, const Duration(minutes: 20));
      tearDownDriver(async);
    });
  });

  test('Seek senza nuova posizione: Ready dopo 3 s con quella attuale', () {
    fakeAsync((async) {
      setUpDriver(async);
      engine.seekDelay = const Duration(seconds: 10);
      send(async,
          command(SyncPlayCommandType.seek, position: const Duration(minutes: 20)));
      async.elapse(const Duration(milliseconds: 2999));
      expect(api.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(api.calls, ['ready']);
      expect(api.readyStates.last.position, const Duration(minutes: 10));
      async.elapse(const Duration(seconds: 10));
      tearDownDriver(async);
    });
  });

  test('Seek superato da un nuovo comando: nessun Ready', () {
    fakeAsync((async) {
      setUpDriver(async);
      engine.seekDelay = const Duration(milliseconds: 200);
      send(async,
          command(SyncPlayCommandType.seek, position: const Duration(minutes: 20)));
      send(async,
          command(SyncPlayCommandType.pause, position: const Duration(minutes: 12)));
      async.elapse(const Duration(seconds: 4));
      expect(api.calls, isEmpty);
      tearDownDriver(async);
    });
  });

  test('chiusura durante un Seek: nessun Ready', () {
    fakeAsync((async) {
      setUpDriver(async);
      engine.seekDelay = const Duration(milliseconds: 200);
      send(async,
          command(SyncPlayCommandType.seek, position: const Duration(minutes: 20)));
      unawaited(driver.dispose());
      async.elapse(const Duration(seconds: 4));
      expect(api.calls, isEmpty);
      tearDownDriver(async);
    });
  });

  test('file non più caricato: i comandi aspettano il prossimo caricamento', () {
    fakeAsync((async) {
      setUpDriver(async);
      driver.onUnloaded();
      send(async,
          command(SyncPlayCommandType.pause, position: const Duration(minutes: 12)));
      expect(engine.calls, isEmpty);
      expect(engine.seeks, isEmpty);
      unawaited(driver.onLoaded());
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      expect(engine.calls, ['pause']);
      expect(engine.seeks, [const Duration(minutes: 12)]);
      tearDownDriver(async);
    });
  });

  test('comando doppio ancora incoerente dopo due tentativi: solo Ready', () {
    fakeAsync((async) {
      setUpDriver(async);
      final seek = command(SyncPlayCommandType.seek,
          position: const Duration(minutes: 20));
      send(async, seek);
      for (var i = 0; i < 3; i++) {
        // Il motore non resta sulla posizione chiesta.
        engine.emitPosition(const Duration(minutes: 5));
        send(async, seek);
      }
      expect(engine.seeks, List.filled(3, const Duration(minutes: 20)));
      expect(api.calls, List.filled(4, 'ready'));
      expect(api.readyStates.last.position, const Duration(minutes: 5));

      // Un comando nuovo riparte da zero.
      final other = command(SyncPlayCommandType.seek,
          position: const Duration(minutes: 30));
      send(async, other);
      engine.emitPosition(const Duration(minutes: 5));
      send(async, other);
      expect(engine.seeks.last, const Duration(minutes: 30));
      expect(engine.seeks, hasLength(5));
      tearDownDriver(async);
    });
  });

  test('Seek durante il buffering: Ready a buffering finito', () {
    fakeAsync((async) {
      setUpDriver(async);
      engine.emitBuffering(true);
      async.flushMicrotasks();
      send(async,
          command(SyncPlayCommandType.seek, position: const Duration(minutes: 20)));
      expect(api.calls, isEmpty);
      engine.emitBuffering(false);
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      tearDownDriver(async);
    });
  });

  test('Stop: pausa', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async, command(SyncPlayCommandType.unpause));
      engine.calls.clear();
      send(async, command(SyncPlayCommandType.stop, item: ''));
      expect(engine.calls, ['pause']);
      tearDownDriver(async);
    });
  });

  test('comandi doppi: non si riapplicano se lo stato è coerente', () {
    fakeAsync((async) {
      setUpDriver(async);
      final unpause = command(SyncPlayCommandType.unpause,
          at: const Duration(milliseconds: 300));
      send(async, unpause);
      send(async, unpause);
      async.elapse(const Duration(milliseconds: 300));
      send(async, unpause);
      expect(engine.calls.where((c) => c == 'play'), hasLength(1));

      final pause = command(SyncPlayCommandType.pause,
          position: const Duration(minutes: 12));
      send(async, pause);
      send(async, pause);
      expect(engine.seeks, [const Duration(minutes: 12)]);

      final seek = command(SyncPlayCommandType.seek,
          position: const Duration(minutes: 20));
      send(async, seek);
      send(async, seek);
      expect(engine.seeks,
          [const Duration(minutes: 12), const Duration(minutes: 20)]);
      // Il server ripete il Seek finché non riceve un Ready valido.
      expect(api.calls.where((c) => c == 'ready'), hasLength(2));
      tearDownDriver(async);
    });
  });

  test('comando doppio con lo stato non coerente: si riapplica', () {
    fakeAsync((async) {
      setUpDriver(async);
      final unpause = command(SyncPlayCommandType.unpause);
      send(async, unpause);
      // Il player si è fermato da solo (es. dopo un "Riprova").
      unawaited(engine.pause());
      engine.calls.clear();
      send(async, unpause);
      expect(engine.calls, ['play']);
      tearDownDriver(async);
    });
  });

  test('comandi per un altro elemento della coda: ignorati', () {
    fakeAsync((async) {
      setUpDriver(async);
      send(async, command(SyncPlayCommandType.pause, item: 'p2'));
      send(async, command(SyncPlayCommandType.unpause, item: 'p2'));
      expect(engine.calls, isEmpty);
      expect(engine.seeks, isEmpty);
      tearDownDriver(async);
    });
  });

  group('buffering', () {
    test('sotto 1 s: il gruppo non lo sa', () {
      fakeAsync((async) {
        setUpDriver(async);
        send(async, command(SyncPlayCommandType.unpause));
        engine.emitBuffering(true);
        async.elapse(const Duration(milliseconds: 900));
        engine.emitBuffering(false);
        async.elapse(const Duration(seconds: 2));
        expect(api.calls, isEmpty);
        tearDownDriver(async);
      });
    });

    test('oltre 1 s: Buffering, poi Ready', () {
      fakeAsync((async) {
        setUpDriver(async);
        send(async, command(SyncPlayCommandType.unpause));
        engine.emitBuffering(true);
        async.elapse(const Duration(milliseconds: 999));
        expect(api.calls, isEmpty);
        async.elapse(const Duration(milliseconds: 2));
        expect(api.calls, ['buffering']);
        expect(api.bufferingStates.single.isPlaying, isTrue);
        engine.emitBuffering(false);
        async.flushMicrotasks();
        expect(api.calls, ['buffering', 'ready']);
        tearDownDriver(async);
      });
    });

    test('a gruppo fermo non si segnala', () {
      fakeAsync((async) {
        setUpDriver(async);
        engine.emitBuffering(true);
        async.elapse(const Duration(seconds: 3));
        expect(api.calls, isEmpty);
        tearDownDriver(async);
      });
    });

    test('dopo il nostro buffering si segue la linea del tempo del Ready', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3), from: unpause);
        // Buffering di 4 s: la vecchia linea del tempo va avanti di 4 s.
        engine.emitBuffering(true);
        async.elapse(const Duration(seconds: 4));
        expect(api.calls, ['buffering']);
        const resumeAt = Duration(minutes: 10, seconds: 3);
        engine.emitPosition(resumeAt);
        engine.emitBuffering(false);
        async.flushMicrotasks();
        expect(api.calls, ['buffering', 'ready']);
        final ready = api.readyStates.last;
        expect(ready.position, resumeAt);
        expect(ready.isPlaying, isTrue);
        // Il server riparte dalla posizione del Ready (senza nuovi comandi
        // per noi): in pari con quella, nessuna correzione.
        final timeline = SyncPlayCommand(
          groupId: 'g1',
          playlistItemId: 'p1',
          when: ready.when,
          position: resumeAt,
          type: SyncPlayCommandType.unpause,
          emittedAt: ready.when,
        );
        engine.seeks.clear();
        runPlayback(async, const Duration(seconds: 8), from: timeline);
        expect(engine.rates, isEmpty);
        expect(engine.seeks, isEmpty);
        tearDownDriver(async);
      });
    });

    test('dopo il nostro buffering un Unpause vero si applica', () {
      fakeAsync((async) {
        setUpDriver(async);
        send(async, command(SyncPlayCommandType.unpause));
        engine.emitBuffering(true);
        async.elapse(const Duration(seconds: 2));
        engine.emitBuffering(false);
        async.flushMicrotasks();
        unawaited(engine.pause());
        engine.calls.clear();
        send(
            async,
            command(SyncPlayCommandType.unpause,
                position: const Duration(minutes: 11),
                at: const Duration(milliseconds: 300)));
        expect(engine.seeks, [const Duration(minutes: 11)]);
        async.elapse(const Duration(milliseconds: 300));
        expect(engine.calls, ['play']);
        tearDownDriver(async);
      });
    });

    test('buffering iniziato prima dell\'Unpause: si segnala dopo 1 s', () {
      fakeAsync((async) {
        setUpDriver(async);
        engine.emitBuffering(true);
        async.elapse(const Duration(seconds: 2));
        expect(api.calls, isEmpty);
        send(async, command(SyncPlayCommandType.unpause));
        async.elapse(const Duration(milliseconds: 999));
        expect(api.calls, isEmpty);
        async.elapse(const Duration(milliseconds: 2));
        expect(api.calls, ['buffering']);
        tearDownDriver(async);
      });
    });
  });

  group('scarto', () {
    test('in pari: nessuna correzione', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 10), from: unpause);
        expect(engine.rates, isEmpty);
        tearDownDriver(async);
      });
    });

    test('300 ms indietro: 1,05×, poi di nuovo 1,0× a scarto recuperato', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3),
            from: unpause, lag: const Duration(milliseconds: 300));
        expect(engine.rates, [1.05]);
        runPlayback(async, const Duration(seconds: 3), from: unpause);
        expect(engine.rates, [1.05, 1.0]);
        tearDownDriver(async);
      });
    });

    test('300 ms avanti: 0,95×', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3),
            from: unpause, lag: const Duration(milliseconds: -300));
        expect(engine.rates, [0.95]);
        tearDownDriver(async);
      });
    });

    test('nei primi 1,5 s dopo la ripresa: nessuna correzione', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(milliseconds: 1400),
            from: unpause, lag: const Duration(seconds: 2));
        expect(engine.rates, isEmpty);
        tearDownDriver(async);
      });
    });

    test('4 s indietro: un salto, poi 5 s senza correzioni', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3),
            from: unpause, lag: const Duration(seconds: 4));
        expect(engine.seeks, hasLength(1));
        expect(engine.seeks.single,
            greaterThan(const Duration(minutes: 10, seconds: 2)));
        runPlayback(async, const Duration(seconds: 4),
            from: unpause, lag: const Duration(seconds: 4));
        expect(engine.seeks, hasLength(1));
        expect(engine.rates, isEmpty);
        tearDownDriver(async);
      });
    });

    test('durante il buffering: nessuna correzione', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        engine.emitBuffering(true);
        runPlayback(async, const Duration(seconds: 4),
            from: unpause, lag: const Duration(milliseconds: 500));
        expect(engine.rates, isEmpty);
        tearDownDriver(async);
      });
    });

    test('un nuovo comando e la chiusura riportano la velocità a 1,0', () {
      fakeAsync((async) {
        setUpDriver(async);
        final unpause = command(SyncPlayCommandType.unpause);
        send(async, unpause);
        runPlayback(async, const Duration(seconds: 3),
            from: unpause, lag: const Duration(milliseconds: 300));
        expect(engine.currentRate, 1.05);
        send(async, command(SyncPlayCommandType.pause));
        expect(engine.currentRate, 1.0);

        final again = command(SyncPlayCommandType.unpause,
            position: const Duration(minutes: 20));
        send(async, again);
        runPlayback(async, const Duration(seconds: 3),
            from: again, lag: const Duration(milliseconds: 300));
        expect(engine.currentRate, 1.05);
        unawaited(driver.dispose());
        async.flushMicrotasks();
        expect(engine.currentRate, 1.0);
        serverClock.stop();
      });
    });
  });

  group('ritardo alla ripartenza', () {
    test('si impara e alla ripresa dopo ci si allinea in anticipo', () {
      fakeAsync((async) {
        setUpDriver(async);
        final first = command(SyncPlayCommandType.unpause,
            at: const Duration(milliseconds: 500));
        send(async, first);
        expect(engine.seeks, isEmpty, reason: 'già a 10:00');
        // mpv parte 400 ms dopo il via: la stima diventa 200 ms.
        runLaggedStart(async, const Duration(seconds: 3),
            from: first, startLag: const Duration(milliseconds: 400));

        send(
            async,
            command(SyncPlayCommandType.pause,
                position: const Duration(minutes: 20)));
        engine.seeks.clear();
        send(
            async,
            command(SyncPlayCommandType.unpause,
                position: const Duration(minutes: 20),
                at: const Duration(milliseconds: 500)));
        expect(engine.seeks,
            [const Duration(minutes: 20, milliseconds: 200)]);
        tearDownDriver(async);
      });
    });

    test('la stima passa al driver dell\'episodio dopo', () {
      fakeAsync((async) {
        final startLag = StartLag();
        setUpDriver(async, startLag: startLag);
        final first = command(SyncPlayCommandType.unpause,
            at: const Duration(milliseconds: 500));
        send(async, first);
        runLaggedStart(async, const Duration(seconds: 3),
            from: first, startLag: const Duration(milliseconds: 400));
        expect(startLag.value, const Duration(milliseconds: 200));
        tearDownDriver(async);

        // Nuovo player (episodio dopo), stesso watch party.
        setUpDriver(async, startLag: startLag);
        send(
            async,
            command(SyncPlayCommandType.unpause,
                at: const Duration(milliseconds: 500)));
        expect(engine.seeks,
            [const Duration(minutes: 10, milliseconds: 200)]);
        tearDownDriver(async);
      });
    });

    test('ripresa con l\'istante già passato: nessuna misura', () {
      fakeAsync((async) {
        setUpDriver(async);
        final first = command(SyncPlayCommandType.unpause);
        send(async, first);
        runLaggedStart(async, const Duration(seconds: 3),
            from: first, startLag: const Duration(milliseconds: 400));

        send(
            async,
            command(SyncPlayCommandType.pause,
                position: const Duration(minutes: 20)));
        engine.seeks.clear();
        send(
            async,
            command(SyncPlayCommandType.unpause,
                position: const Duration(minutes: 20),
                at: const Duration(milliseconds: 500)));
        expect(engine.seeks, isEmpty, reason: 'nessun anticipo: già a 20:00');
        tearDownDriver(async);
      });
    });
  });

  test('riallineamento: segnalato con onResync', () {
    fakeAsync((async) {
      setUpDriver(async);
      final unpause = command(SyncPlayCommandType.unpause);
      send(async, unpause);
      runPlayback(async, const Duration(seconds: 3),
          from: unpause, lag: const Duration(seconds: 4));
      expect(resyncs, 1);
      tearDownDriver(async);
    });
  });

  test('onDrift: l\'ultimo scarto misurato', () {
    fakeAsync((async) {
      setUpDriver(async);
      final unpause = command(SyncPlayCommandType.unpause);
      send(async, unpause);
      runPlayback(async, const Duration(seconds: 3),
          from: unpause, lag: const Duration(milliseconds: 300));
      expect(lastDrift, const Duration(milliseconds: 300));
      tearDownDriver(async);
    });
  });

  test('dopo il rientro nel gruppo si rimanda Ready', () {
    fakeAsync((async) {
      setUpDriver(async);
      unawaited(driver.onRejoined());
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      expect(api.readyStates.last.position, const Duration(minutes: 10));
      tearDownDriver(async);
    });
  });

  test('rientro prima che il file sia aperto: niente', () {
    fakeAsync((async) {
      setUpDriver(async, load: false);
      unawaited(driver.onRejoined());
      async.flushMicrotasks();
      expect(api.calls, isEmpty);
      tearDownDriver(async);
    });
  });

  test('video non aperto: il gruppo non ci aspetta, finché non si riapre', () {
    fakeAsync((async) {
      setUpDriver(async);
      driver.onUnloaded(failed: true);
      driver.onUnloaded(failed: true);
      async.flushMicrotasks();
      expect(api.calls, ['ignore-wait true']);

      unawaited(driver.onLoaded());
      async.flushMicrotasks();
      expect(api.calls, ['ignore-wait true', 'ignore-wait false', 'ready']);
      tearDownDriver(async);
    });
  });

  test(
      'esclusione dall\'attesa rimasta dall\'episodio prima (non aperto): a '
      'file aperto il gruppo torna ad aspettarci, poi Ready', () {
    fakeAsync((async) {
      setUpDriver(async, load: false, ignoringWait: true);
      unawaited(driver.onLoaded());
      async.flushMicrotasks();
      expect(api.calls, ['ignore-wait false', 'ready']);
      expect(waitExclusion.ignoring, isFalse);
      tearDownDriver(async);
    });
  });

  test('file non più pronto senza errore: il gruppo aspetta come prima', () {
    fakeAsync((async) {
      setUpDriver(async);
      driver.onUnloaded();
      async.flushMicrotasks();
      expect(api.calls, isEmpty);
      tearDownDriver(async);
    });
  });
}
