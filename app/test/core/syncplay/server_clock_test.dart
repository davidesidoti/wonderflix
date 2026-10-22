import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/server_clock.dart';

/// Server con l'orologio avanti di [offset]. Ogni misura usa la coppia
/// successiva di [legs] (andata, ritorno); l'ultima si ripete.
ServerTimeFetcher fakeServer(Duration offset,
    [List<(Duration, Duration)> legs = const [(Duration.zero, Duration.zero)]]) {
  var index = 0;
  return () async {
    final (out, back) = legs[min(index++, legs.length - 1)];
    await Future<void>.delayed(out);
    final serverTime = clock.now().toUtc().add(offset);
    await Future<void>.delayed(back);
    return (serverReceived: serverTime, serverSent: serverTime);
  };
}

void main() {
  test('ClockSample: offset, ritardo e ping', () {
    final t0 = DateTime.utc(2026, 9, 30, 10);
    final sample = ClockSample(
      sent: t0,
      serverReceived: t0.add(const Duration(milliseconds: 2050)),
      serverSent: t0.add(const Duration(milliseconds: 2060)),
      received: t0.add(const Duration(milliseconds: 110)),
    );
    expect(sample.offset, const Duration(seconds: 2));
    expect(sample.delay, const Duration(milliseconds: 100));
    expect(sample.ping, const Duration(milliseconds: 50));
  });

  test('prima misura, conversioni e ping', () {
    fakeAsync((async) {
      const ms50 = Duration(milliseconds: 50);
      final pings = <Duration>[];
      final serverClock = ServerClock(
        fetch: fakeServer(const Duration(seconds: 2), [(ms50, ms50)]),
        onPing: pings.add,
      );
      var first = false;
      unawaited(serverClock.firstSample.then((_) => first = true));
      expect(serverClock.ready, isFalse);
      expect(serverClock.offset, Duration.zero);

      serverClock.start();
      async.elapse(const Duration(milliseconds: 100));
      expect(first, isTrue);
      expect(serverClock.ready, isTrue);
      expect(serverClock.offset, const Duration(seconds: 2));
      expect(serverClock.ping, ms50);
      expect(pings, [ms50]);

      final local = DateTime.utc(2026, 9, 30, 10);
      expect(serverClock.toServer(local), local.add(const Duration(seconds: 2)));
      expect(serverClock.toLocal(local),
          local.subtract(const Duration(seconds: 2)));
      expect(serverClock.serverNow().difference(clock.now().toUtc()),
          const Duration(seconds: 2));
      serverClock.stop();
    });
  });

  test('3 misure a 1 s di distanza, poi una ogni 60 s', () {
    fakeAsync((async) {
      var calls = 0;
      final serverClock = ServerClock(fetch: () async {
        calls++;
        final now = clock.now().toUtc();
        return (serverReceived: now, serverSent: now);
      });
      serverClock.start();
      async.flushMicrotasks();
      expect(calls, 1);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 2);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 3);
      async.elapse(const Duration(seconds: 59));
      expect(calls, 3);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 4);
      async.elapse(const Duration(seconds: 60));
      expect(calls, 5);

      serverClock.stop();
      async.elapse(const Duration(minutes: 5));
      expect(calls, 5);
    });
  });

  test('usa la misura con il ritardo più basso', () {
    fakeAsync((async) {
      // Andata e ritorno asimmetrici falsano l'offset: la misura migliore è
      // quella con il ritardo più basso (20+20 ms, offset esatto).
      final serverClock = ServerClock(
        fetch: fakeServer(const Duration(seconds: 1), const [
          (Duration(milliseconds: 300), Duration(milliseconds: 100)),
          (Duration(milliseconds: 20), Duration(milliseconds: 20)),
          (Duration(milliseconds: 150), Duration(milliseconds: 50)),
        ]),
      );
      serverClock.start();
      async.elapse(const Duration(milliseconds: 500));
      expect(serverClock.offset, const Duration(milliseconds: 1100));
      async.elapse(const Duration(seconds: 5));
      expect(serverClock.offset, const Duration(seconds: 1));
      expect(serverClock.ping, const Duration(milliseconds: 20));
      serverClock.stop();
    });
  });

  test('misure non riuscite: si riprova, senza diventare pronto', () {
    fakeAsync((async) {
      var calls = 0;
      final serverClock = ServerClock(fetch: () async {
        calls++;
        throw Exception('rete');
      });
      serverClock.start();
      async.elapse(const Duration(seconds: 3));
      expect(calls, 3);
      expect(serverClock.ready, isFalse);
      serverClock.stop();
    });
  });

  test('una risposta che arriva dopo stop() viene ignorata', () {
    fakeAsync((async) {
      final serverClock = ServerClock(
        fetch: fakeServer(Duration.zero, const [
          (Duration(milliseconds: 100), Duration(milliseconds: 100)),
        ]),
      );
      serverClock.start();
      async.elapse(const Duration(milliseconds: 50));
      serverClock.stop();
      async.elapse(const Duration(seconds: 5));
      expect(serverClock.ready, isFalse);
    });
  });
}
