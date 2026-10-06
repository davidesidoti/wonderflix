import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_poller.dart';

void main() {
  const every = Duration(seconds: 5);

  test('accesa: legge subito, poi a ogni intervallo', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 1);
      async.elapse(const Duration(seconds: 4));
      expect(reads, 1);
      async.elapse(const Duration(seconds: 1));
      expect(reads, 2);
      async.elapse(const Duration(seconds: 10));
      expect(reads, 4);

      poller.dispose();
    });
  });

  test('l\'intervallo parte dalla fine della lettura: mai due insieme', () {
    fakeAsync((async) {
      var reads = 0;
      var running = 0;
      var overlap = false;
      final poller = AdminPoller(
        read: () async {
          reads++;
          running++;
          if (running > 1) overlap = true;
          await Future<void>.delayed(const Duration(seconds: 8));
          running--;
        },
        interval: every,
      );

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 1);
      // 8 s di lettura e 4 di attesa: la seconda non è ancora partita.
      async.elapse(const Duration(seconds: 12));
      expect(reads, 1);
      async.elapse(const Duration(seconds: 1));
      expect(reads, 2);
      expect(overlap, isFalse);

      poller.dispose();
      async.elapse(const Duration(seconds: 10));
    });
  });

  test('now durante una lettura: una sola lettura in più, subito dopo', () {
    fakeAsync((async) {
      final pending = <Completer<void>>[];
      final poller = AdminPoller(
        read: () {
          final read = Completer<void>();
          pending.add(read);
          return read.future;
        },
        interval: every,
      );

      poller.start();
      async.elapse(Duration.zero);
      expect(pending, hasLength(1));

      var done = false;
      unawaited(poller.now().then((_) => done = true));
      unawaited(poller.now());
      async.flushMicrotasks();
      expect(pending, hasLength(1));

      pending[0].complete();
      async.flushMicrotasks();
      expect(pending, hasLength(2));
      expect(done, isFalse);

      pending[1].complete();
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(pending, hasLength(2));

      async.elapse(every);
      expect(pending, hasLength(3));
      pending[2].complete();
      poller.dispose();
    });
  });

  test('spenta non legge; riaccesa legge subito', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 1);
      poller.stop();
      async.elapse(const Duration(seconds: 20));
      expect(reads, 1);
      expect(poller.active, isFalse);

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 2);
      poller.dispose();
    });
  });

  test('un intervallo nuovo vale da subito', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      async.elapse(Duration.zero);
      poller.interval = const Duration(seconds: 2);
      async.elapse(const Duration(seconds: 2));
      expect(reads, 2);
      async.elapse(const Duration(seconds: 2));
      expect(reads, 3);
      poller.dispose();
    });
  });

  test('una lettura che fallisce non ferma la rilettura', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(
        read: () async {
          reads++;
          if (reads == 1) throw StateError('rete');
        },
        interval: every,
      );

      poller.start();
      async.elapse(Duration.zero);
      async.elapse(every);
      expect(reads, 2);
      poller.dispose();
    });
  });

  test('chiusa: niente più letture, e now non legge', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      async.elapse(Duration.zero);
      poller.dispose();
      unawaited(poller.now());
      poller.start();
      async.elapse(const Duration(seconds: 30));
      expect(reads, 1);
    });
  });

  test('una lettura che lancia subito, senza essere async, non blocca nulla', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(
        read: () {
          reads++;
          throw StateError('subito');
        },
        interval: every,
      );

      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 1);
      async.elapse(every);
      expect(reads, 2, reason: 'la rilettura continua');

      poller.stop();
      poller.start();
      async.elapse(Duration.zero);
      expect(reads, 3, reason: 'spenta e riaccesa legge subito');

      unawaited(poller.now());
      async.flushMicrotasks();
      expect(reads, 4, reason: 'now legge davvero');
      poller.dispose();
    });
  });

  test('spenta durante una lettura: finita quella, non ne programma altre', () {
    fakeAsync((async) {
      final pending = <Completer<void>>[];
      final poller = AdminPoller(
        read: () {
          final read = Completer<void>();
          pending.add(read);
          return read.future;
        },
        interval: every,
      );

      poller.start();
      async.elapse(Duration.zero);
      expect(pending, hasLength(1));

      poller.stop();
      pending[0].complete();
      async.elapse(const Duration(seconds: 30));
      expect(pending, hasLength(1));
      poller.dispose();
    });
  });

  test('accesa durante una lettura: nessuna lettura in più subito', () {
    fakeAsync((async) {
      final pending = <Completer<void>>[];
      final poller = AdminPoller(
        read: () {
          final read = Completer<void>();
          pending.add(read);
          return read.future;
        },
        interval: every,
      );

      // Una lettura chiesta a poller spento, e poi lo si accende.
      unawaited(poller.now());
      async.flushMicrotasks();
      expect(pending, hasLength(1));
      poller.start();
      async.elapse(const Duration(seconds: 30));
      expect(pending, hasLength(1), reason: 'quella in corso basta');

      pending[0].complete();
      async.elapse(const Duration(seconds: 4));
      expect(pending, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(pending, hasLength(2), reason: 'la prossima dopo un intervallo');
      pending[1].complete();
      poller.dispose();
    });
  });

  test('now da spenta: legge una volta sola e non programma altre letture', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      unawaited(poller.now());
      async.elapse(const Duration(seconds: 30));
      expect(reads, 1);
      expect(poller.active, isFalse);
      poller.dispose();
    });
  });

  test('un intervallo nuovo subito dopo start non ritarda la prima lettura', () {
    fakeAsync((async) {
      var reads = 0;
      final poller = AdminPoller(read: () async => reads++, interval: every);

      poller.start();
      poller.interval = const Duration(seconds: 60);
      async.elapse(Duration.zero);
      expect(reads, 1, reason: 'la prima lettura resta a zero');

      async.elapse(const Duration(seconds: 59));
      expect(reads, 1);
      async.elapse(const Duration(seconds: 1));
      expect(reads, 2, reason: 'la seconda col ritmo nuovo');
      poller.dispose();
    });
  });
}
