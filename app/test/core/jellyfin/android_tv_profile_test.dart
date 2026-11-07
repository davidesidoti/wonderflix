import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/android_tv_profile.dart';
import 'package:wonderflix/core/jellyfin/device_profile.dart';

DecoderCaps caps({bool tenBit = false, List<Map<String, Object>>? video}) =>
    DecoderCaps.fromMap({
      'video':
          video ??
          [
            {
              'mime': 'video/avc',
              'maxWidth': 1920,
              'maxHeight': 1080,
              'tenBit': false,
            },
            {
              'mime': 'video/hevc',
              'maxWidth': 4096,
              'maxHeight': 2176,
              'tenBit': tenBit,
            },
          ],
      'audio': [
        'audio/mp4a-latm',
        'audio/mpeg',
        'audio/ac3',
        'audio/eac3',
        'audio/unknown',
      ],
      'hdrTypes': <String>[],
    });

Map direct(Map profile) =>
    (profile['DirectPlayProfiles'] as List).single as Map;

Map codec(Map profile, String name) => (profile['CodecProfiles'] as List)
    .cast<Map>()
    .singleWhere((c) => c['Codec'] == name);

List<Map> conditions(Map c, String property) => (c['Conditions'] as List)
    .cast<Map>()
    .where((e) => e['Property'] == property)
    .toList();

void main() {
  test('nome, bitrate, contenitori e codec dai mime', () {
    final p = buildAndroidTvDeviceProfile(caps(), maxBitrate: 5000000);
    expect(p['Name'], 'WonderFlix (Android TV)');
    expect(p['MaxStreamingBitrate'], 5000000);
    expect(direct(p)['Type'], 'Video');
    expect(direct(p)['Container'], 'mkv,webm,mp4,m4v,mov,ts');
    expect(direct(p)['VideoCodec'], 'h264,hevc');
    expect(direct(p)['AudioCodec'], 'aac,mp3,ac3,eac3');
  });

  test('tutti i mime noti', () {
    final p = buildAndroidTvDeviceProfile(
      DecoderCaps.fromMap({
        'video': [
          for (final m in [
            'video/avc',
            'video/hevc',
            'video/x-vnd.on2.vp9',
            'video/av01',
          ])
            {'mime': m, 'maxWidth': 3840, 'maxHeight': 2160, 'tenBit': true},
        ],
        'audio': [
          'audio/mp4a-latm',
          'audio/mpeg',
          'audio/ac3',
          'audio/eac3',
          'audio/vnd.dts',
          'audio/flac',
          'audio/opus',
          'audio/vorbis',
        ],
      }),
    );
    expect(direct(p)['VideoCodec'], 'h264,hevc,vp9,av1');
    expect(direct(p)['AudioCodec'], 'aac,mp3,ac3,eac3,dts,flac,opus,vorbis');
  });

  test('HEVC senza 10 bit: profondità massima 8; con 10 bit nessuna', () {
    final eight = codec(buildAndroidTvDeviceProfile(caps()), 'hevc');
    expect(
      conditions(eight, 'VideoBitDepth').single['Condition'],
      'LessThanEqual',
    );
    expect(conditions(eight, 'VideoBitDepth').single['Value'], '8');
    final ten = codec(buildAndroidTvDeviceProfile(caps(tenBit: true)), 'hevc');
    expect(conditions(ten, 'VideoBitDepth'), isEmpty);
    // H.264: sempre 8 bit (Hi10P non ha decoder hardware sulle TV), anche
    // se HEVC fa 10 bit.
    for (final c in [caps(), caps(tenBit: true)]) {
      final h264 = conditions(
        codec(buildAndroidTvDeviceProfile(c), 'h264'),
        'VideoBitDepth',
      ).single;
      expect(h264['Condition'], 'LessThanEqual');
      expect(h264['Value'], '8');
      expect(h264['IsRequired'], false);
    }
  });

  test('limiti di risoluzione per codec', () {
    final p = buildAndroidTvDeviceProfile(caps());
    expect(conditions(codec(p, 'h264'), 'Width').single['Value'], '1920');
    expect(conditions(codec(p, 'h264'), 'Height').single['Value'], '1080');
    expect(
      conditions(codec(p, 'hevc'), 'Width').single['Condition'],
      'LessThanEqual',
    );
    expect(conditions(codec(p, 'hevc'), 'Width').single['Value'], '4096');
    expect(conditions(codec(p, 'hevc'), 'Height').single['Value'], '2176');
  });

  test(
    'decoder dello stesso mime: dimensioni massime e 10 bit se uno lo ha',
    () {
      final c = caps(
        video: [
          {
            'mime': 'video/hevc',
            'maxWidth': 1920,
            'maxHeight': 2160,
            'tenBit': false,
          },
          {
            'mime': 'video/hevc',
            'maxWidth': 4096,
            'maxHeight': 1080,
            'tenBit': true,
          },
        ],
      );
      expect(c.video, hasLength(1));
      expect(c.video.single.maxWidth, 4096);
      expect(c.video.single.maxHeight, 2160);
      expect(c.video.single.tenBit, isTrue);
    },
  );

  test('Fire Stick: HEVC 4K Main10 senza HDR, nessuna condizione su HDR', () {
    final p = buildAndroidTvDeviceProfile(caps(tenBit: true));
    expect(direct(p)['VideoCodec'], contains('hevc'));
    final conds = codec(p, 'hevc')['Conditions'] as List;
    expect(
      conds.map((e) => (e as Map)['Property']),
      unorderedEquals(['Width', 'Height']),
    );
  });

  test('senza decoder niente direct play', () {
    final p = buildAndroidTvDeviceProfile(DecoderCaps.fromMap({}));
    expect(p['DirectPlayProfiles'], isEmpty);
  });

  test('transcodifica come mpv ma copia anche HEVC; sottotitoli uguali', () {
    final p = buildAndroidTvDeviceProfile(caps());
    final mpv = buildDeviceProfile();
    final tv = (p['TranscodingProfiles'] as List).single as Map;
    final mpvProfile = (mpv['TranscodingProfiles'] as List).single as Map;
    expect(tv['VideoCodec'], 'h264,hevc');
    expect(
      {...tv}..remove('VideoCodec'),
      {...mpvProfile}..remove('VideoCodec'),
    );
    // Senza decoder HEVC il server non deve produrre HEVC.
    final noHevc = buildAndroidTvDeviceProfile(
      caps(
        video: [
          {
            'mime': 'video/avc',
            'maxWidth': 1920,
            'maxHeight': 1080,
            'tenBit': false,
          },
        ],
      ),
    );
    expect(
      ((noHevc['TranscodingProfiles'] as List).single as Map)['VideoCodec'],
      'h264',
    );
    expect(p['SubtitleProfiles'], mpv['SubtitleProfiles']);
  });
}
