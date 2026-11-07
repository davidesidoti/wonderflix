import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/video/default_video_engine.dart';
import 'package:wonderflix/core/video/media3_engine.dart';
import 'package:wonderflix/core/video/video_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('wonderflix/player');
  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall)> handlers;
  late StreamController<dynamic> events;
  late Media3Engine engine;

  const playerId = 7;

  void emit(String type, [Object? value, int id = playerId]) =>
      events.add({'id': id, 'type': type, 'value': value});

  Iterable<MethodCall> called(String method) =>
      calls.where((call) => call.method == method);

  setUp(() {
    calls = [];
    handlers = {'create': (_) => playerId};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handlers[call.method]?.call(call);
        });
    events = StreamController<dynamic>.broadcast(sync: true);
    engine = Media3Engine(channel: channel, events: events.stream);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    events.close();
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('open', () {
    test(
      'create una volta, poi open con startMs; completa dopo loaded',
      () async {
        var done = false;
        final opening = engine
            .open(
              const VideoSource(
                url: 'http://x/v.mkv',
                headers: {'Authorization': 't'},
                start: Duration(seconds: 90),
              ),
            )
            .then((_) => done = true);
        await flush();
        expect(called('create'), hasLength(1));
        expect(called('open').single.arguments, {
          'id': playerId,
          'url': 'http://x/v.mkv',
          'headers': {'Authorization': 't'},
          'startMs': 90000,
        });
        expect(done, isFalse);
        emit('loaded');
        await opening;
        expect(done, isTrue);

        // Una seconda apertura non crea un altro player.
        final second = engine.open(const VideoSource(url: 'http://x/w.mkv'));
        await flush();
        emit('loaded');
        await second;
        expect(called('create'), hasLength(1));
      },
    );

    test('error prima di loaded: EngineOpenException e stop', () async {
      final opening = engine.open(const VideoSource(url: 'u'));
      await flush();
      emit('error', 'rete');
      await expectLater(
        opening,
        throwsA(
          isA<EngineOpenException>().having(
            (e) => e.message,
            'message',
            'rete',
          ),
        ),
      );
      expect(called('stop'), hasLength(1));
    });

    test('timeout dopo 60 s senza eventi', () {
      fakeAsync((async) {
        Object? error;
        engine.open(const VideoSource(url: 'u')).catchError((Object e) {
          error = e;
        });
        async.flushMicrotasks();
        async.elapse(Media3Engine.openTimeout - const Duration(seconds: 1));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(error, isA<EngineOpenException>());
        expect((error! as EngineOpenException).message, 'timeout');
        expect(called('stop'), hasLength(1));
      });
    });

    test(
      'dispose durante open: open fallisce, dispose sul canale, stream muti',
      () async {
        final opening = engine.open(const VideoSource(url: 'u'));
        opening.ignore();
        await flush();
        final positions = <Duration>[];
        engine.positionStream.listen(positions.add);
        await engine.dispose();
        await expectLater(opening, throwsA(isA<EngineOpenException>()));
        expect(called('dispose').single.arguments, {'id': playerId});
        emit('position', 1000);
        await flush();
        expect(positions, isEmpty);
      },
    );
  });

  group('eventi', () {
    test('quelli di un altro id vengono ignorati', () async {
      final opening = engine.open(const VideoSource(url: 'u'));
      await flush();
      emit('loaded', null, playerId + 1);
      emit('position', 5000, playerId + 1);
      emit('playing', true, playerId + 1);
      var done = false;
      opening.then((_) => done = true);
      await flush();
      expect(done, isFalse);
      expect(engine.position, Duration.zero);
      expect(engine.playing, isFalse);
      emit('loaded');
      await opening;
    });

    test('stream e getter', () async {
      final opening = engine.open(const VideoSource(url: 'u'));
      await flush();
      emit('loaded');
      await opening;

      final positions = <Duration>[];
      final durations = <Duration>[];
      final buffers = <Duration>[];
      final playing = <bool>[];
      final buffering = <bool>[];
      final completed = <bool>[];
      final errors = <String>[];
      engine.positionStream.listen(positions.add);
      engine.durationStream.listen(durations.add);
      engine.bufferStream.listen(buffers.add);
      engine.playingStream.listen(playing.add);
      engine.bufferingStream.listen(buffering.add);
      engine.completedStream.listen(completed.add);
      engine.errorStream.listen(errors.add);

      var frame = false;
      engine.firstFrame.then((_) => frame = true);
      await flush();
      expect(frame, isFalse);

      emit('position', 1500);
      emit('duration', 60000);
      emit('buffer', 9000);
      emit('playing', true);
      emit('buffering', true);
      emit('completed', true);
      emit('firstFrame');
      emit('error', 'decoder');
      await flush();

      expect(positions, [const Duration(milliseconds: 1500)]);
      expect(durations, [const Duration(seconds: 60)]);
      expect(buffers, [const Duration(seconds: 9)]);
      expect(playing, [true]);
      expect(buffering, [true]);
      expect(completed, [true]);
      expect(errors, ['decoder']);
      expect(frame, isTrue);
      expect(engine.position, const Duration(milliseconds: 1500));
      expect(engine.duration, const Duration(seconds: 60));
      expect(engine.buffer, const Duration(seconds: 9));
      expect(engine.playing, isTrue);
    });

    test('playBlockedStream non emette, selectsEmbeddedTracks è true', () {
      expect(engine.selectsEmbeddedTracks, isTrue);
      expect(engine.playBlockedStream, emitsDone);
    });
  });

  group('comandi', () {
    setUp(() async {
      // Il player esiste: un comando qualsiasi lo crea.
      await engine.play();
      calls.clear();
    });

    test('play, pause, seek, rate', () async {
      await engine.pause();
      await engine.play();
      await engine.seek(const Duration(seconds: 3));
      await engine.setRate(1.25);
      expect(
        [for (final c in calls) c.method],
        ['pause', 'play', 'seek', 'setRate'],
      );
      expect(calls[2].arguments, {'id': playerId, 'ms': 3000});
      expect(calls[3].arguments, {'id': playerId, 'rate': 1.25});
    });

    test('volume, tracce, ritardo e scala dei sottotitoli', () async {
      await engine.setVolume(50);
      await engine.selectAudio(null);
      await engine.selectSubtitle('2:1');
      await engine.setSubtitleDelay(const Duration(milliseconds: -1500));
      await engine.setSubtitleScale(1.5);
      expect(calls.map((c) => c.arguments), [
        {'id': playerId, 'volume': 0.5},
        {'id': playerId, 'track': null},
        {'id': playerId, 'track': '2:1'},
        {'id': playerId, 'ms': -1500},
        {'id': playerId, 'scale': 1.5},
      ]);
    });

    test('addSubtitle passa url, titolo e lingua e restituisce id', () async {
      handlers['addSubtitle'] = (_) => '1:4';
      final id = await engine.addSubtitle(
        'http://x/s.srt',
        title: 'Italiano',
        language: 'ita',
      );
      expect(id, '1:4');
      expect(calls.single.arguments, {
        'id': playerId,
        'url': 'http://x/s.srt',
        'title': 'Italiano',
        'language': 'ita',
      });
    });

    test('tracks converte tipo e formatId', () async {
      handlers['tracks'] = (_) => [
        {
          'id': 'a1',
          'type': 'audio',
          'formatId': '3',
          'title': 'Stereo',
          'language': 'ita',
        },
        {'id': 's1', 'type': 'subtitle', 'formatId': '1:0'},
        {'id': 'v1', 'type': 'video', 'formatId': null},
        {'id': 'x', 'type': 'altro'},
      ];
      final tracks = await engine.tracks();
      expect(tracks, hasLength(3));
      expect(tracks[0].id, 'a1');
      expect(tracks[0].type, EngineTrackType.audio);
      expect(tracks[0].ffIndex, 2);
      expect(tracks[0].external, isFalse);
      expect(tracks[0].title, 'Stereo');
      expect(tracks[0].language, 'ita');
      expect(tracks[1].type, EngineTrackType.subtitle);
      expect(tracks[1].ffIndex, isNull);
      expect(tracks[1].external, isTrue);
      expect(tracks[2].type, EngineTrackType.video);
      expect(tracks[2].ffIndex, isNull);
    });
  });

  test('parseFormatId', () {
    expect(parseFormatId('3'), (ffIndex: 2, external: false));
    expect(parseFormatId('0:3'), (ffIndex: 2, external: false));
    expect(parseFormatId('1:0'), (ffIndex: null, external: true));
    expect(parseFormatId(null), (ffIndex: null, external: false));
    expect(parseFormatId('abc'), (ffIndex: null, external: false));
  });

  test('su Android TV si sceglie Media3Engine', () {
    expect(
      createVideoEngine(hardwareDecoding: true, androidTv: true),
      isA<Media3Engine>(),
    );
  });
}
