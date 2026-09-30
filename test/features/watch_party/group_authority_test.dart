import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/watch_party/group_authority.dart';

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
      () async {
    await authority.seekTo(const Duration(minutes: 30));
    expect(engine.calls, ['pause']);
    expect(engine.seeks, [const Duration(minutes: 30)]);
    expect(api.calls, ['seek ${const Duration(minutes: 30)}']);
  });

  test('errori di rete: nessuna eccezione verso il player', () async {
    api.error = const ServerUnreachableException();
    await authority.play();
    await authority.pause();
    await authority.seekTo(Duration.zero);
    expect(api.calls, ['unpause', 'pause', 'seek 0:00:00.000000']);
  });
}
