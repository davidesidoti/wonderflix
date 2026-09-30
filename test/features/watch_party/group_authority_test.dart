import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/watch_party/group_authority.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';

import '../../support/playback_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeVideoEngine engine;
  late FakeSyncPlayApi api;
  late GroupAuthority authority;

  setUp(() {
    engine = FakeVideoEngine();
    api = FakeSyncPlayApi();
    authority = GroupAuthority(api: api, engine: engine);
  });

  test('play chiede la ripresa al gruppo, senza muovere il motore', () async {
    await authority.play();
    expect(api.calls, ['unpause']);
    expect(engine.calls, isEmpty);
  });

  test('pause ferma subito anche il motore', () async {
    await authority.play();
    await engine.play();
    engine.calls.clear();
    await authority.pause();
    expect(engine.calls, ['pause']);
    expect(api.calls.last, 'pause');
  });

  test('seekTo mette in pausa sulla posizione scelta e la chiede al gruppo',
      () {
    fakeAsync((async) {
      unawaited(authority.seekTo(const Duration(minutes: 30)));
      async.flushMicrotasks();
      expect(engine.calls, ['pause']);
      expect(engine.seeks, [const Duration(minutes: 30)]);
      expect(api.calls, isEmpty);
      async.elapse(GroupAuthority.seekDebounce);
      expect(api.calls, ['seek ${const Duration(minutes: 30)}']);
    });
  });

  test('salti ripetuti (tasto tenuto): un solo Seek con l\'ultima posizione',
      () {
    fakeAsync((async) {
      for (var i = 1; i <= 10; i++) {
        unawaited(authority.seekTo(Duration(seconds: 10 * i)));
        async.elapse(const Duration(milliseconds: 30));
      }
      expect(engine.seeks, hasLength(10));
      expect(api.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 369));
      expect(api.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(api.calls, ['seek ${const Duration(seconds: 100)}']);
      async.elapse(const Duration(seconds: 1));
      expect(api.calls, hasLength(1));
    });
  });

  test('play con un salto in sospeso: prima il Seek, poi la ripresa', () {
    fakeAsync((async) {
      unawaited(authority.seekTo(const Duration(minutes: 5)));
      async.elapse(const Duration(milliseconds: 100));
      unawaited(authority.play());
      async.flushMicrotasks();
      expect(api.calls, ['seek ${const Duration(minutes: 5)}', 'unpause']);
      async.elapse(const Duration(seconds: 1));
      expect(api.calls, hasLength(2));
    });
  });

  test('dispose annulla il salto in sospeso', () {
    fakeAsync((async) {
      unawaited(authority.seekTo(const Duration(minutes: 5)));
      async.flushMicrotasks();
      authority.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(api.calls, isEmpty);
    });
  });

  test('errori di rete: nessuna eccezione verso il player', () {
    fakeAsync((async) {
      api.error = const ServerUnreachableException();
      unawaited(authority.play());
      unawaited(authority.pause());
      unawaited(authority.seekTo(Duration.zero));
      async.elapse(GroupAuthority.seekDebounce);
      expect(api.calls, ['unpause', 'pause', 'seek 0:00:00.000000']);
    });
  });

  test('le azioni si annunciano subito come mie', () {
    fakeAsync((async) {
      final actions = <(PartyNoticeKind, Duration?)>[];
      final announcing = GroupAuthority(
        api: api,
        engine: engine,
        onAction: (kind, {position}) => actions.add((kind, position)),
      );
      unawaited(announcing.pause());
      async.flushMicrotasks();
      unawaited(announcing.seekTo(const Duration(minutes: 5)));
      unawaited(announcing.seekTo(const Duration(minutes: 6)));
      async.flushMicrotasks();
      expect(actions, [(PartyNoticeKind.paused, null)]);

      async.elapse(GroupAuthority.seekDebounce);
      expect(actions.last,
          (PartyNoticeKind.seeked, const Duration(minutes: 6)));

      unawaited(announcing.play());
      async.flushMicrotasks();
      expect(actions.last, (PartyNoticeKind.resumed, null));
      expect(actions, hasLength(3));
      announcing.dispose();
    });
  });
}
