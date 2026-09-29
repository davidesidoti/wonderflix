import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/playback_api.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late PlaybackApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = PlaybackApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('playbackInfo invia profilo, posizione e tracce', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'PlaySessionId': 'ps1',
          'MediaSources': [
            {'Id': 'ms1', 'SupportsDirectPlay': true, 'MediaStreams': []},
          ],
        });
    final result = await api.playbackInfo(
      'm1',
      userId: 'u1',
      start: const Duration(minutes: 1),
      maxBitrate: 8000000,
      allowDirect: false,
      mediaSourceId: 'ms1',
      audioStreamIndex: 2,
      subtitleStreamIndex: -1,
    );
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Items/m1/PlaybackInfo');
    final body = request.data as Map<String, dynamic>;
    expect(body['UserId'], 'u1');
    expect(body['StartTimeTicks'], 600000000);
    expect(body['MaxStreamingBitrate'], 8000000);
    expect(body['EnableDirectPlay'], false);
    expect(body['EnableDirectStream'], false);
    expect(body['EnableTranscoding'], true);
    expect(body['MediaSourceId'], 'ms1');
    expect(body['AudioStreamIndex'], 2);
    expect(body['SubtitleStreamIndex'], -1);
    expect(body['DeviceProfile'], isA<Map<String, dynamic>>());
    expect(result.playSessionId, 'ps1');
    expect(result.mediaSources.single.supportsDirectPlay, isTrue);
  });

  test('playbackInfo senza indici non li invia', () async {
    adapter.handler = (_) => const FakeResponse(200, {'MediaSources': []});
    await api.playbackInfo('m1',
        userId: 'u1',
        start: Duration.zero,
        maxBitrate: 1,
        allowDirect: true);
    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body['EnableDirectPlay'], true);
    expect(body.containsKey('AudioStreamIndex'), isFalse);
    expect(body.containsKey('SubtitleStreamIndex'), isFalse);
    expect(body.containsKey('MediaSourceId'), isFalse);
  });

  test('report di inizio, avanzamento e fine', () async {
    const report = PlaybackReport(
      itemId: 'm1',
      mediaSourceId: 'ms1',
      playSessionId: 'ps1',
      position: Duration(seconds: 90),
      isPaused: true,
      isMuted: false,
      volume: 80,
      audioStreamIndex: 1,
      subtitleStreamIndex: null,
      playMethod: PlayMethod.directPlay,
    );
    await api.reportStart(report);
    expect(adapter.requests.last.path, '/Sessions/Playing');
    expect(adapter.requests.last.data, {
      'ItemId': 'm1',
      'MediaSourceId': 'ms1',
      'PlaySessionId': 'ps1',
      'PositionTicks': 900000000,
      'IsPaused': true,
      'IsMuted': false,
      'VolumeLevel': 80,
      'AudioStreamIndex': 1,
      'SubtitleStreamIndex': -1,
      'PlayMethod': 'DirectPlay',
      'CanSeek': true,
    });

    await api.reportProgress(report);
    expect(adapter.requests.last.path, '/Sessions/Playing/Progress');

    await api.reportStopped(report);
    expect(adapter.requests.last.path, '/Sessions/Playing/Stopped');
    expect(adapter.requests.last.data, {
      'ItemId': 'm1',
      'MediaSourceId': 'ms1',
      'PlaySessionId': 'ps1',
      'PositionTicks': 900000000,
      'Failed': false,
    });
  });

  test('userData legge minutaggio e stato', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'PlaybackPositionTicks': 5,
          'Played': false,
          'PlayedPercentage': 12.5,
        });
    final data = await api.userData('u1', 'm1');
    expect(adapter.requests.last.method, 'GET');
    expect(adapter.requests.last.path, '/UserItems/m1/UserData');
    expect(adapter.requests.last.queryParameters, {'userId': 'u1'});
    expect(data.playbackPositionTicks, 5);
    expect(data.playedPercentage, 12.5);
  });

  test('mediaSegments: intro, crediti e tipi sconosciuti', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {'Type': 'Intro', 'StartTicks': 100000000, 'EndTicks': 900000000},
            {'Type': 'Outro', 'StartTicks': 24000000000, 'EndTicks': 25200000000},
            {'Type': 'Nuovo', 'StartTicks': 0, 'EndTicks': 10},
          ],
          'TotalRecordCount': 3,
        });
    final segments = await api.mediaSegments('e4');
    expect(adapter.requests.last.path, '/MediaSegments/e4');
    expect(segments.map((s) => s.type), [
      MediaSegmentType.intro,
      MediaSegmentType.outro,
      MediaSegmentType.unknown,
    ]);
    expect(segments.first.start, const Duration(seconds: 10));
    expect(segments.first.end, const Duration(seconds: 90));
    expect(segments[1].start, const Duration(minutes: 40));
  });
}
