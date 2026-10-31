import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/space/space_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SpaceApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SpaceApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Future<SpaceFailure> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } on SpaceException catch (e) {
      return e.failure;
    }
    fail('nessuna eccezione');
  }

  test('StartPostsKindAndKey', () async {
    adapter.handler = (_) => const FakeResponse(202, {'Id': 'op1'});
    expect(await api.start('Movie', 'movie:12'), 'op1');
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Space/Operations'));
    expect(request.data, {'Kind': 'Movie', 'Key': 'movie:12'});
  });

  test('BusyAndNotReadyAreRead', () async {
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'Busy'});
    expect(await failure(() => api.start('Movie', 'k')), SpaceFailure.busy);
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'NotReady'});
    expect(await failure(() => api.start('Movie', 'k')), SpaceFailure.notReady);
    adapter.handler = (_) => const FakeResponse(404, {'Reason': 'Unknown'});
    expect(await failure(() => api.start('Movie', 'k')), SpaceFailure.unknown);
    adapter.handler = (_) => const FakeResponse(404);
    expect(await failure(() => api.operation('x')), SpaceFailure.notFound);
    expect(await failure(() => api.dropPending('h')), SpaceFailure.notFound);
    adapter.handler = (_) => const FakeResponse(400);
    expect(await failure(() => api.start('', '')), SpaceFailure.invalid);
    adapter.handler = (_) => const FakeResponse(403);
    expect(await failure(() => api.overview()), SpaceFailure.forbidden);
    adapter.handler = (_) => const FakeResponse(503);
    expect(await failure(() => api.overview()), SpaceFailure.server);
    adapter.handler = (_) => const FakeResponse(200, {'Boh': 1});
    expect(await failure(() => api.overview()), SpaceFailure.invalid);
  });

  test('UnkeepSendsTheKeyInTheQuery', () async {
    await api.unkeep('movie:12');
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('DELETE', '/WonderFlixWatchParty/Space/Kept'));
    expect(request.queryParameters, {'key': 'movie:12'});
    expect(request.uri.toString(), contains('?key=movie%3A12'));
  });

  test('KeepRecalculateAndDropPendingHitTheirEndpoints', () async {
    await api.keep('movie:1', 'Film');
    await api.recalculate();
    await api.dropPending('abc');
    expect(
        adapter.requests.map((r) => (r.method, r.path)),
        [
          ('POST', '/WonderFlixWatchParty/Space/Kept'),
          ('POST', '/WonderFlixWatchParty/Space/Recalculate'),
          ('DELETE', '/WonderFlixWatchParty/Space/Pending/abc'),
        ]);
    expect(adapter.requests.first.data, {'Key': 'movie:1', 'Title': 'Film'});
  });

  test('ImportLightenPostsTheKeyAndReadsTheReason', () async {
    await api.importLighten('season:142:1');
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Space/Lighten/Import'));
    expect(request.data, {'Key': 'season:142:1'});

    adapter.handler = (_) => const FakeResponse(404, {'Reason': 'Unknown'});
    expect(await failure(() => api.importLighten('k')), SpaceFailure.unknown);
    adapter.handler = (_) => const FakeResponse(502, {'Reason': 'NoFiles'});
    try {
      await api.importLighten('k');
      fail('nessuna eccezione');
    } on SpaceException catch (e) {
      expect((e.failure, e.reason), (SpaceFailure.server, 'NoFiles'));
    }
  });
}
