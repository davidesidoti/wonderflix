import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/subtitles/subtitle_models.dart';
import 'package:wonderflix/core/subtitles/subtitles_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

Map<String, dynamic> subtitleJson({
  String id = 's1',
  String name = 'Dune.2024.it',
  bool hash = false,
  int? downloads,
}) =>
    {
      'Id': id,
      'ProviderName': 'OpenSubtitles',
      'Name': name,
      'Language': 'ita',
      'Format': 'srt',
      'CommunityRating': 7.5,
      'DownloadCount': ?downloads,
      'IsHashMatch': hash,
      'HearingImpaired': false,
      'Forced': false,
      'MachineTranslated': true,
    };

RemoteSubtitle sub(String name, {bool hash = false, int? downloads}) =>
    RemoteSubtitle.fromJson(
        subtitleJson(id: name, name: name, hash: hash, downloads: downloads));

void main() {
  late FakeAdapter adapter;
  late SubtitlesApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SubtitlesApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Future<SubtitlesFailure> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } on SubtitlesException catch (e) {
      return e.failure;
    }
    fail('nessuna eccezione');
  }

  test('search chiama la rotta con lingua e perfectMatch e legge i risultati',
      () async {
    adapter.handler =
        (_) => FakeResponse(200, [subtitleJson(downloads: 12, hash: true)]);
    final results = await api.search('e1', 'ita', perfectMatch: true);
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('GET', '/WonderFlixWatchParty/Subtitles/e1/Search'));
    expect(request.queryParameters, {'language': 'ita', 'perfectMatch': true});
    final result = results.single;
    expect((result.id, result.providerName, result.language, result.format),
        ('s1', 'OpenSubtitles', 'ita', 'srt'));
    expect((result.communityRating, result.downloadCount), (7.5, 12));
    expect((result.isHashMatch, result.machineTranslated, result.forced), (true, true, false));

    await api.search('e1', 'eng');
    expect(adapter.requests.last.queryParameters, {'language': 'eng'});
  });

  test('download manda SubtitleId', () async {
    await api.download('e1', 's1');
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Subtitles/e1/Download'));
    expect(request.data, {'SubtitleId': 's1'});
  });

  test('upload manda Data in base64', () async {
    await api.upload(
        'e1',
        SubtitleUpload(
            language: 'ita',
            format: 'srt',
            isForced: true,
            isHearingImpaired: false,
            bytes: Uint8List.fromList(utf8.encode('1\n00:00'))));
    final request = adapter.requests.single;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Subtitles/e1/Upload'));
    expect(request.data, {
      'Language': 'ita',
      'Format': 'srt',
      'IsForced': true,
      'IsHearingImpaired': false,
      'Data': base64Encode(utf8.encode('1\n00:00')),
    });
  });

  test('delete chiama Jellyfin', () async {
    await api.delete('e1', 3);
    final request = adapter.requests.single;
    expect((request.method, request.path), ('DELETE', '/Videos/e1/Subtitles/3'));
  });

  test('i codici diventano errori tipati; 502 è failed', () async {
    adapter.handler = (_) => const FakeResponse(502, {'Reason': 'DownloadFailed'});
    expect(await failure(() => api.download('e1', 's1')), SubtitlesFailure.failed);
    adapter.handler = (_) => const FakeResponse(502);
    expect(await failure(() => api.search('e1', 'ita')), SubtitlesFailure.failed);
    adapter.handler = (_) => const FakeResponse(404);
    expect(await failure(() => api.search('e1', 'ita')), SubtitlesFailure.unavailable);
    adapter.handler = (_) => const FakeResponse(403);
    expect(await failure(() => api.delete('e1', 1)), SubtitlesFailure.forbidden);
    adapter.handler = (_) => const FakeResponse(401);
    expect(await failure(() => api.delete('e1', 1)), SubtitlesFailure.forbidden);
    adapter.handler = (_) => const FakeResponse(400);
    expect(await failure(() => api.download('e1', 's1')), SubtitlesFailure.invalid);
    adapter.handler = (_) => const FakeResponse(500);
    expect(await failure(() => api.download('e1', 's1')), SubtitlesFailure.network);
  });

  test('sortSubtitles mette prima i sincronizzati poi per download', () {
    final sorted = sortSubtitles([
      sub('b', downloads: 5),
      sub('z'),
      sub('a'),
      sub('c', downloads: 50),
      sub('h', hash: true, downloads: 1),
      sub('a2', downloads: 5),
    ]);
    expect(sorted.map((s) => s.name), ['h', 'c', 'a2', 'b', 'a', 'z']);
  });
}
