import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/downloads_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late DownloadsApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = DownloadsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Future<DownloadsFailure> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } on DownloadsException catch (e) {
      return e.failure;
    }
    fail('nessuna eccezione');
  }

  test('SearchWaitsUpToTwoAndAHalfMinutes', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Key': 'movie:1',
          'Kind': 'Movie',
          'Title': 'Film',
          'RuntimeMinutes': 100,
          'ValidCount': 0,
          'TotalCount': 0,
        });
    final search = await api.search('movie:1');
    final request = adapter.requests.single;
    expect(request.path, '/WonderFlixWatchParty/Downloads/Search');
    expect(request.queryParameters, {'key': 'movie:1'});
    expect(request.receiveTimeout, const Duration(seconds: 150));
    expect(search.title, 'Film');
  });

  test('GrabPostsKeyGuidAndIndexer', () async {
    await api.grab('movie:1', 'g1', 3);
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Downloads/Grab'));
    expect(request.data, {'Key': 'movie:1', 'Guid': 'g1', 'IndexerId': 3});
    // Il plugin può rifare la ricerca dentro il grab (fino a 2 minuti).
    expect(request.receiveTimeout, const Duration(seconds: 150));
  });

  test('ConflictIsExpired', () async {
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'Expired'});
    expect(await failure(() => api.grab('k', 'g', 1)), DownloadsFailure.expired);
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'Busy'});
    expect(await failure(() => api.grab('k', 'g', 1)), DownloadsFailure.busy);
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'Boh'});
    expect(await failure(() => api.grab('k', 'g', 1)), DownloadsFailure.expired);
    adapter.handler = (_) => const FakeResponse(409);
    expect(await failure(() => api.grab('k', 'g', 1)), DownloadsFailure.expired);
  });

  test('NotFoundIsUnavailable', () async {
    adapter.handler = (_) => const FakeResponse(404);
    expect(await failure(() => api.overview()), DownloadsFailure.unavailable);
  });

  test('BadRequestIsInvalid', () async {
    adapter.handler = (_) => const FakeResponse(400);
    expect(await failure(() => api.search('x')), DownloadsFailure.invalid);
  });

  test('BusyAndUnavailableAreMapped', () async {
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'Busy'});
    expect(await failure(() => api.accept('k')), DownloadsFailure.busy);
    adapter.handler = (_) => const FakeResponse(503, {'Reason': 'Unavailable'});
    expect(await failure(() => api.searchNow('k')), DownloadsFailure.arrUnavailable);
    adapter.handler = (_) => const FakeResponse(503);
    expect(await failure(() => api.searchNow('k')), DownloadsFailure.network);
    adapter.handler = (_) => const FakeResponse(502, {'Reason': 'Refused'});
    expect(await failure(() => api.grab('k', 'g', 1)), DownloadsFailure.refused);
    adapter.handler = (_) => const FakeResponse(502);
    expect(await failure(() => api.grab('k', 'g', 1)), DownloadsFailure.network);
    adapter.handler = (_) => const FakeResponse(403);
    expect(await failure(() => api.overview()), DownloadsFailure.forbidden);
    adapter.handler = (_) => const FakeResponse(200, {'Boh': 1});
    expect(await failure(() => api.overview()), DownloadsFailure.network);
  });
}
