import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';

void main() {
  test('PlaybackInfo: sorgente, tracce e indici predefiniti', () {
    final result = PlaybackInfoResult.fromJson({
      'PlaySessionId': 'ps1',
      'MediaSources': [
        {
          'Id': 'ms1',
          'SupportsDirectPlay': true,
          'DefaultAudioStreamIndex': 1,
          'DefaultSubtitleStreamIndex': -1,
          'MediaStreams': [
            {'Index': 0, 'Type': 'Video', 'Codec': 'hevc'},
            {
              'Index': 1,
              'Type': 'Audio',
              'Language': 'ita',
              'DisplayTitle': 'Italiano',
              'IsDefault': true,
            },
            {
              'Index': 2,
              'Type': 'Subtitle',
              'Codec': 'PGSSUB',
              'DeliveryMethod': 'Embed',
            },
            {
              'Index': 3,
              'Type': 'Subtitle',
              'Codec': 'srt',
              'IsExternal': true,
              'IsTextSubtitleStream': true,
              'DeliveryMethod': 'External',
              'DeliveryUrl': '/Videos/m1/ms1/Subtitles/3/0/Stream.srt',
            },
            {'Index': 4, 'Type': 'Attachment'},
          ],
        },
      ],
    });
    expect(result.playSessionId, 'ps1');
    expect(result.errorCode, isNull);
    final source = result.mediaSources.single;
    expect(source.id, 'ms1');
    expect(source.supportsDirectPlay, isTrue);
    expect(source.transcodingUrl, isNull);
    expect(source.defaultAudioStreamIndex, 1);
    expect(source.defaultSubtitleStreamIndex, -1);
    expect(source.audioStreams.map((s) => s.index), [1]);
    expect(source.subtitleStreams.map((s) => s.index), [2, 3]);
    expect(source.stream(1)?.displayTitle, 'Italiano');
    expect(source.stream(1)?.isDefault, isTrue);
    expect(source.stream(4)?.kind, StreamKind.other);
    expect(source.stream(9), isNull);
    expect(source.stream(2)?.deliveredExternally, isFalse);
    expect(source.stream(3)?.deliveredExternally, isTrue);
    expect(source.stream(3)?.isExternal, isTrue);
  });

  test('PlaybackInfo con errore', () {
    final result = PlaybackInfoResult.fromJson(
        {'ErrorCode': 'NotAllowed', 'MediaSources': []});
    expect(result.errorCode, 'NotAllowed');
    expect(result.mediaSources, isEmpty);
  });

  test('resolveServerUrl mantiene il sotto-percorso del server', () {
    final server = Uri.parse('https://host.example.com/jellyfin');
    expect(resolveServerUrl(server, '/videos/m1/master.m3u8?a=1'),
        'https://host.example.com/jellyfin/videos/m1/master.m3u8?a=1');
    expect(resolveServerUrl(server, 'videos/m1/x.srt'),
        'https://host.example.com/jellyfin/videos/m1/x.srt');
    expect(resolveServerUrl(server, 'https://cdn.example.com/s.srt'),
        'https://cdn.example.com/s.srt');
  });
}
