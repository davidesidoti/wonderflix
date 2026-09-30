import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/server_clock.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/watch_party/group_playback_driver.dart';

import '../../support/playback_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeVideoEngine engine;
  late FakeSyncPlayApi api;
  late ServerClock serverClock;
  late StreamController<SyncPlayCommand> commands;
  late GroupPlaybackDriver driver;

  /// Tutto dentro la zona finta: file aperto a 10:00, orologio pronto
  /// (scarto zero). Con [load] il file è già caricato e il `Ready` iniziale
  /// è già partito (le chiamate vengono azzerate).
  void setUpDriver(FakeAsync async, {bool load = true}) {
    engine = FakeVideoEngine();
    unawaited(engine
        .open(const VideoSource(url: 'x', start: Duration(minutes: 10))));
    api = FakeSyncPlayApi();
    serverClock = ServerClock(fetch: () async {
      final now = clock.now().toUtc();
      return (serverReceived: now, serverSent: now);
    })
      ..start();
    commands = StreamController<SyncPlayCommand>.broadcast();
    driver = GroupPlaybackDriver(
      engine: engine,
      api: api,
      clock: serverClock,
      playlistItemId: 'p1',
      commands: commands.stream,
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
}
