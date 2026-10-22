import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/progress_reporter.dart';

import '../../support/playback_fakes.dart';

PlaybackReport reportAt(Duration position) => PlaybackReport(
      itemId: 'm1',
      mediaSourceId: 'ms1',
      playSessionId: 'ps1',
      position: position,
      isPaused: false,
      isMuted: false,
      volume: 100,
      audioStreamIndex: 1,
      subtitleStreamIndex: null,
      playMethod: PlayMethod.directPlay,
    );

void main() {
  test('inizio, avanzamento ogni 10 s e a ogni evento, fine una sola volta',
      () {
    fakeAsync((async) {
      final api = FakePlaybackApi();
      var position = Duration.zero;
      final reporter =
          ProgressReporter(api: api, snapshot: () => reportAt(position));

      unawaited(reporter.start());
      async.flushMicrotasks();
      expect(api.started, hasLength(1));

      async.elapse(const Duration(seconds: 25));
      expect(api.progress, hasLength(2));

      reporter.onEvent();
      async.flushMicrotasks();
      expect(api.progress, hasLength(3));

      position = const Duration(minutes: 5);
      unawaited(reporter.stop());
      unawaited(reporter.stop());
      async.flushMicrotasks();
      expect(api.stopped.single.position, const Duration(minutes: 5));

      async.elapse(const Duration(seconds: 30));
      reporter.onEvent();
      async.flushMicrotasks();
      expect(api.progress, hasLength(3), reason: 'niente report dopo la fine');
    });
  });

  test('la fine non aspetta più di 2 s', () {
    fakeAsync((async) {
      final api = FakePlaybackApi()..delay = const Duration(seconds: 10);
      final reporter =
          ProgressReporter(api: api, snapshot: () => reportAt(Duration.zero));
      unawaited(reporter.start());
      var done = false;
      unawaited(reporter.stop().then((_) => done = true));
      async.elapse(const Duration(milliseconds: 1900));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 200));
      expect(done, isTrue);
      // Lascia terminare le richieste lente.
      async.elapse(const Duration(seconds: 10));
    });
  });

  test('gli errori di rete non interrompono la riproduzione', () async {
    final api = FakePlaybackApi()..error = const ServerUnreachableException();
    final reporter =
        ProgressReporter(api: api, snapshot: () => reportAt(Duration.zero));
    await reporter.start();
    reporter.onEvent();
    await reporter.stop();
    expect(api.started, hasLength(1));
    expect(api.stopped, hasLength(1));
  });

  test('senza start, stop non invia nulla', () async {
    final api = FakePlaybackApi();
    await ProgressReporter(api: api, snapshot: () => reportAt(Duration.zero))
        .stop();
    expect(api.stopped, isEmpty);
  });
}
