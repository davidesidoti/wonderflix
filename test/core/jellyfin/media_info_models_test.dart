import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/media_info_models.dart';

Map<String, dynamic> source({
  String id = 'v1',
  String? path = '/media/film/Dune.mkv',
  List<Map<String, dynamic>> streams = const [],
}) =>
    {
      'Id': id,
      'Name': 'Dune 4K',
      'Container': 'mkv',
      'Size': 123456,
      'RunTimeTicks': 72000000000,
      'Bitrate': 8000000,
      'Path': ?path,
      'MediaStreams': streams,
    };

void main() {
  test('versioni, video, audio e sottotitoli dal JSON di Jellyfin', () {
    final info = ItemMediaInfo.fromItemJson({
      'MediaSources': [
        source(streams: [
          {
            'Index': 0,
            'Type': 'Video',
            'Codec': 'hevc',
            'Width': 3840,
            'Height': 2160,
            'RealFrameRate': 23.976,
            'VideoRange': 'HDR',
          },
          {
            'Index': 1,
            'Type': 'Audio',
            'Codec': 'eac3',
            'Language': 'ita',
            'Title': 'Italiano',
            'Channels': 6,
            'IsDefault': true,
          },
          {
            'Index': 2,
            'Type': 'Subtitle',
            'Codec': 'subrip',
            'Language': 'eng',
            'IsExternal': true,
            'IsForced': true,
            'IsHearingImpaired': true,
          },
          {'Index': 3, 'Type': 'Attachment'},
        ]),
      ],
    });
    final v = info.versions.single;
    expect((v.id, v.name, v.container, v.size, v.bitrate),
        ('v1', 'Dune 4K', 'mkv', 123456, 8000000));
    expect(v.duration, const Duration(hours: 2));
    expect(v.fileName, 'Dune.mkv');
    expect(v.video!.codec, 'hevc');
    expect((v.video!.width, v.video!.height), (3840, 2160));
    expect(v.video!.fps, closeTo(23.976, 0.001));
    expect(v.video!.range, 'HDR');
    final audio = v.audio.single;
    expect((audio.index, audio.language, audio.codec, audio.title, audio.channels,
            audio.isDefault),
        (1, 'ita', 'eac3', 'Italiano', 6, true));
    final sub = v.subtitles.single;
    expect((sub.index, sub.language, sub.codec, sub.isExternal, sub.isForced,
            sub.isHearingImpaired),
        (2, 'eng', 'subrip', true, true, true));
  });

  test('fileName è solo il nome, con / e con \\', () {
    String? name(String? path) =>
        ItemMediaInfo.fromItemJson({
          'MediaSources': [source(path: path)]
        }).versions.single.fileName;
    expect(name('/media/film/Dune.mkv'), 'Dune.mkv');
    expect(name(r'D:\Film\Dune Parte Due.mkv'), 'Dune Parte Due.mkv');
    expect(name(r'\\nas\film/Dune.mkv'), 'Dune.mkv');
    expect(name('Dune.mkv'), 'Dune.mkv');
    expect(name(null), isNull);
    expect(name(''), isNull);
  });

  test('externalSubtitleIndexes', () {
    final info = ItemMediaInfo.fromItemJson({
      'MediaSources': [
        source(id: 'a', streams: [
          {'Index': 2, 'Type': 'Subtitle', 'IsExternal': true},
          {'Index': 3, 'Type': 'Subtitle', 'IsExternal': false},
        ]),
        source(id: 'b', streams: [
          {'Index': 7, 'Type': 'Subtitle', 'IsExternal': true},
          {'Index': 8, 'Type': 'Audio', 'IsExternal': true},
        ]),
      ],
    });
    expect(externalSubtitleIndexes(info), {2, 7});
  });

  test('senza MediaSources: nessuna versione', () {
    expect(ItemMediaInfo.fromItemJson({}).versions, isEmpty);
    expect(ItemMediaInfo.fromItemJson({'MediaSources': null}).versions, isEmpty);
    final bare = ItemMediaInfo.fromItemJson({
      'MediaSources': [
        {'Id': 'v'}
      ]
    }).versions.single;
    expect(bare.video, isNull);
    expect(bare.duration, isNull);
    expect(bare.audio, isEmpty);
    expect(bare.subtitles, isEmpty);
  });
}
