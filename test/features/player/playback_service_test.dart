import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/device_profile.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/playback_service.dart';

import '../../support/playback_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakePlaybackApi api;

  setUp(() => api = FakePlaybackApi());

  PlaybackService service({Uri? serverUrl, bool breakDirectPlay = false}) =>
      PlaybackService(
        api: api,
        serverUrl: serverUrl ?? testServerUrl,
        authorization: () => 'MediaBrowser Token="t1"',
        breakDirectPlay: breakDirectPlay,
      );

  test('direct play: stream statico con header e posizione', () async {
    final plan = await service().prepare(
        itemId: 'm1', userId: 'u1', start: const Duration(minutes: 3));
    final call = api.playbackInfoCalls.single;
    expect(call.itemId, 'm1');
    expect(call.allowDirect, isTrue);
    expect(call.start, const Duration(minutes: 3));
    expect(call.maxBitrate, originalQualityBitrate);
    expect(call.audioStreamIndex, isNull);
    expect(call.subtitleStreamIndex, isNull);
    expect(plan.method, PlayMethod.directPlay);
    expect(plan.isTranscode, isFalse);
    expect(plan.playSessionId, 'ps1');
    expect(plan.source.url,
        'https://media.example.com/Videos/m1/stream?static=true&mediaSourceId=ms1&playSessionId=ps1');
    expect(plan.source.headers, {'Authorization': 'MediaBrowser Token="t1"'});
    expect(plan.source.start, const Duration(minutes: 3));
    expect(plan.audioIndex, 1);
    expect(plan.subtitleIndex, 3);
  });

  test('il server non consente il direct play: HLS sotto il sotto-percorso',
      () async {
    api.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final plan = await service(
            serverUrl: Uri.parse('https://host.example.com/jellyfin'))
        .prepare(itemId: 'm1', userId: 'u1');
    expect(plan.method, PlayMethod.transcode);
    expect(plan.source.url,
        'https://host.example.com/jellyfin/videos/m1/master.m3u8?MediaSourceId=ms1&PlaySessionId=ps1');
  });

  test('forceTranscode: chiede solo la transcodifica e la usa', () async {
    final plan = await service().prepare(
      itemId: 'm1',
      userId: 'u1',
      forceTranscode: true,
      mediaSourceId: 'ms1',
      audioIndex: 2,
      subtitleIndex: -1,
    );
    final call = api.playbackInfoCalls.single;
    expect(call.allowDirect, isFalse);
    expect(call.mediaSourceId, 'ms1');
    expect(call.audioStreamIndex, 2);
    expect(call.subtitleStreamIndex, -1);
    expect(plan.method, PlayMethod.transcode);
    expect(plan.audioIndex, 2);
    expect(plan.subtitleIndex, isNull, reason: '-1 = nessun sottotitolo');
  });

  test('nessun sottotitolo predefinito', () async {
    api.onPlaybackInfo = (_) => testPlaybackInfo(defaultSubtitle: null);
    final plan = await service().prepare(itemId: 'm1', userId: 'u1');
    expect(plan.subtitleIndex, isNull);
  });

  test('errori: ErrorCode, nessuna sorgente, nessun modo di riprodurre',
      () async {
    api.onPlaybackInfo = (_) => testPlaybackInfo(errorCode: 'NotAllowed');
    await expectLater(
        service().prepare(itemId: 'm1', userId: 'u1'),
        throwsA(isA<PlaybackUnavailableException>()
            .having((e) => e.code, 'code', 'NotAllowed')));

    api.onPlaybackInfo =
        (_) => PlaybackInfoResult.fromJson({'MediaSources': []});
    await expectLater(service().prepare(itemId: 'm1', userId: 'u1'),
        throwsA(isA<PlaybackUnavailableException>()));

    api.onPlaybackInfo = (_) => PlaybackInfoResult.fromJson({
          'MediaSources': [
            {'Id': 'ms1', 'SupportsDirectPlay': false},
          ],
        });
    await expectLater(service().prepare(itemId: 'm1', userId: 'u1'),
        throwsA(isA<PlaybackUnavailableException>()));
  });

  test('burnsIn: sottotitoli non esterni in transcodifica, Encode sempre',
      () async {
    api.onPlaybackInfo = (_) => testPlaybackInfo(directPlay: false);
    final transcode = await service().prepare(itemId: 'm1', userId: 'u1');
    expect(transcode.burnsIn(4), isTrue, reason: 'PGS bruciato');
    expect(transcode.burnsIn(6), isTrue, reason: 'PGS esterno bruciato');
    expect(transcode.burnsIn(3), isFalse, reason: 'ASS estratto a parte');
    expect(transcode.burnsIn(null), isFalse);

    api.onPlaybackInfo = (_) => testPlaybackInfo();
    final direct = await service().prepare(itemId: 'm1', userId: 'u1');
    expect(direct.burnsIn(4), isFalse, reason: 'PGS interno: lo mostra mpv');
    expect(direct.burnsIn(5), isFalse, reason: 'SRT esterno caricato a parte');
    expect(direct.burnsIn(6), isTrue,
        reason: 'PGS esterno: il server lo consegna solo bruciato');
    expect(direct.burnsIn(null), isFalse);
  });

  test('subtitleUrl e breakDirectPlay', () async {
    final plan = await service().prepare(itemId: 'm1', userId: 'u1');
    expect(service().subtitleUrl(plan.mediaSource.stream(5)!),
        'https://media.example.com/Videos/m1/ms1/Subtitles/5/0/Stream.srt');

    final broken =
        await service(breakDirectPlay: true).prepare(itemId: 'm1', userId: 'u1');
    expect(broken.source.url, contains('mediaSourceId=wonderflix-test-invalid'));
  });
}
