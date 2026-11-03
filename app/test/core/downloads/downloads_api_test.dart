import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
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

  test('StartSearchPostsKeyAndAgain', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Key': 'movie:1',
          'State': 'Running',
          'StartedAt': '2026-11-01T10:00:00+01:00',
          'Service': 'Radarr',
          'Result': null,
        });
    final status = await api.startSearch('movie:1');
    var request = adapter.requests.single;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Downloads/SearchStart'));
    expect(request.data, {'Key': 'movie:1', 'Again': false});
    // Parte e risponde subito: niente attesa lunga.
    expect(request.receiveTimeout, isNot(DownloadsApi.searchTimeout));
    expect(status.state, DownloadSearchJobState.running);

    adapter.requests.clear();
    await api.startSearch('movie:1', again: true);
    request = adapter.requests.single;
    expect(request.data, {'Key': 'movie:1', 'Again': true});
  });

  test('SearchStatusGetsTheKey', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Key': 'movie:1',
          'State': 'None',
          'StartedAt': null,
          'Service': 'Radarr',
          'Result': null,
        });
    final status = await api.searchStatus('movie:1');
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('GET', '/WonderFlixWatchParty/Downloads/SearchStatus'));
    expect(request.queryParameters, {'key': 'movie:1'});
    expect(request.receiveTimeout, isNot(DownloadsApi.searchTimeout));
    expect(status.state, DownloadSearchJobState.none);
  });

  test('SearchJobCallsMapErrors', () async {
    adapter.handler = (_) => const FakeResponse(400);
    expect(await failure(() => api.startSearch('x')), DownloadsFailure.invalid);
    expect(await failure(() => api.searchStatus('x')), DownloadsFailure.invalid);
    adapter.handler = (_) => const FakeResponse(404);
    expect(await failure(() => api.searchStatus('x')),
        DownloadsFailure.unavailable);
    // Stato sconosciuto: risposta di forma inattesa.
    adapter.handler = (_) => const FakeResponse(200, {'Key': 'x', 'State': 'Boh'});
    expect(await failure(() => api.searchStatus('x')), DownloadsFailure.network);
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

  test('GrabCanLighten', () async {
    await api.grab('movie:1', 'g1', 3, lighten: true);
    expect(adapter.requests.single.data,
        {'Key': 'movie:1', 'Guid': 'g1', 'IndexerId': 3, 'Lighten': true});
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

  test('AGrabRefusedForAnExistingTorrentCarriesIt', () async {
    adapter.handler = (_) => const FakeResponse(
        502, {'Reason': 'Refused', 'Hash': 'abc', 'Name': 'Film.2024'});
    try {
      await api.grab('k', 'g', 1);
      fail('nessuna eccezione');
    } on DownloadsException catch (e) {
      expect(e.failure, DownloadsFailure.refused);
      expect(e.existing?.hash, 'abc');
      expect(e.existing?.name, 'Film.2024');
    }
  });

  test('ARefusedWithoutHashOrNameHasNoExistingTorrent', () async {
    for (final body in <Map<String, Object?>>[
      {'Reason': 'Refused'},
      {'Reason': 'Refused', 'Name': 'Film'},
      {'Reason': 'Refused', 'Hash': '', 'Name': 'Film'},
      {'Reason': 'Refused', 'Hash': 'abc', 'Name': ''},
      {'Reason': 'Refused', 'Hash': 1, 'Name': 'Film'},
    ]) {
      adapter.handler = (_) => FakeResponse(502, body);
      try {
        await api.grab('k', 'g', 1);
        fail('nessuna eccezione');
      } on DownloadsException catch (e) {
        expect(e.failure, DownloadsFailure.refused);
        expect(e.existing, isNull);
      }
    }
  });

  test('ImportExistingPostsKeyAndHashAndMapsErrors', () async {
    await api.importExisting('k', 'abc');
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Downloads/ImportExisting'));
    expect(request.data, {'Key': 'k', 'Hash': 'abc'});
    expect(request.receiveTimeout, DownloadsApi.searchTimeout);

    adapter.requests.clear();
    await api.importExisting('k', 'abc', lighten: true);
    expect(adapter.requests.single.data,
        {'Key': 'k', 'Hash': 'abc', 'Lighten': true});

    for (final (status, reason, expected) in <(int, String, DownloadsFailure)>[
      (409, 'Changed', DownloadsFailure.changed),
      (502, 'NoFiles', DownloadsFailure.noFiles),
      (502, 'ImportFailed', DownloadsFailure.importFailed),
      (503, 'Unavailable', DownloadsFailure.arrUnavailable),
    ]) {
      adapter.handler = (_) => FakeResponse(status, {'Reason': reason});
      expect(await failure(() => api.importExisting('k', 'abc')), expected);
    }
  });

  test('ActionsPostTheKey', () async {
    for (final (call, name) in <(Future<void> Function(), String)>[
      (() => api.grabBest('k'), 'GrabBest'),
      (() => api.snooze('k'), 'Snooze'),
      (() => api.importBlocked('k'), 'Import'),
      (() => api.discard('k'), 'Discard'),
      (() => api.hunt('k'), 'Hunt'),
    ]) {
      adapter.requests.clear();
      await call();
      final request = adapter.requests.single;
      expect((request.method, request.path),
          ('POST', '/WonderFlixWatchParty/Downloads/$name'));
      expect(request.data, {'Key': 'k'});
    }
  });

  test('RemoveUnknownPostsTheDownload', () async {
    await api.removeUnknown('Sonarr', 'D1');
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Downloads/RemoveUnknown'));
    expect(request.data, {'Service': 'Sonarr', 'DownloadId': 'D1'});
    expect(request.receiveTimeout, DownloadsApi.searchTimeout);
  });

  test('GrabBestWaitsForTheSearch', () async {
    await api.grabBest('k');
    expect(adapter.requests.single.receiveTimeout, DownloadsApi.searchTimeout);
  });

  test('NewReasonsAreMapped', () async {
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'NothingToGrab'});
    expect(await failure(() => api.grabBest('k')), DownloadsFailure.nothingToGrab);
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'Changed'});
    expect(await failure(() => api.discard('k')), DownloadsFailure.changed);
    expect(await failure(() => api.hunt('k')), DownloadsFailure.changed);
    adapter.handler = (_) => const FakeResponse(502, {'Reason': 'NoFiles'});
    expect(await failure(() => api.importBlocked('k')), DownloadsFailure.noFiles);
    adapter.handler = (_) => const FakeResponse(502, {'Reason': 'ImportFailed'});
    expect(await failure(() => api.importBlocked('k')),
        DownloadsFailure.importFailed);
    adapter.handler = (_) => const FakeResponse(409, {'Reason': 'Busy'});
    expect(await failure(() => api.snooze('k')), DownloadsFailure.busy);
    adapter.handler = (_) => const FakeResponse(409);
    expect(await failure(() => api.snooze('k')), DownloadsFailure.expired);
  });
}
