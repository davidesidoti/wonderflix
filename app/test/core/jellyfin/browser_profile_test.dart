import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/browser_profile.dart';

const chromeHevc = BrowserCapabilities(
  h264: true,
  hevc: true,
  hevcMain10: true,
  vp9: true,
  av1: true,
  aac: true,
  mp3: true,
  opus: true,
  flac: true,
  ac3: false,
  eac3: false,
  mkv: true,
  fmp4Hls: true,
  nativeHls: false,
  isFirefox: false,
);

const chromeNoHevc = BrowserCapabilities(
  h264: true,
  hevc: false,
  hevcMain10: false,
  vp9: true,
  av1: true,
  aac: true,
  mp3: true,
  opus: true,
  flac: true,
  ac3: false,
  eac3: false,
  mkv: true,
  fmp4Hls: true,
  nativeHls: false,
  isFirefox: false,
);

const edge = BrowserCapabilities(
  h264: true,
  hevc: true,
  hevcMain10: true,
  vp9: true,
  av1: true,
  aac: true,
  mp3: true,
  opus: true,
  flac: true,
  ac3: true,
  eac3: true,
  mkv: true,
  fmp4Hls: true,
  nativeHls: false,
  isFirefox: false,
);

const firefox = BrowserCapabilities(
  h264: true,
  hevc: false,
  hevcMain10: false,
  vp9: true,
  av1: true,
  aac: true,
  mp3: true,
  opus: true,
  flac: true,
  ac3: false,
  eac3: false,
  mkv: false,
  fmp4Hls: true,
  nativeHls: false,
  isFirefox: true,
);

Map<String, dynamic> transcoding(Map<String, dynamic> profile) =>
    (profile['TranscodingProfiles'] as List).single as Map<String, dynamic>;

List<String> directContainers(Map<String, dynamic> profile) => [
      for (final p in profile['DirectPlayProfiles'] as List)
        (p as Map)['Container'] as String,
    ];

String? subtitleMethod(Map<String, dynamic> profile, String format) =>
    (profile['SubtitleProfiles'] as List)
        .cast<Map>()
        .where((p) => p['Format'] == format)
        .map((p) => p['Method'] as String)
        .firstOrNull;

void main() {
  test('chromeHevc: HEVC copiato in fMP4, mkv nel direct play', () {
    final profile = buildBrowserDeviceProfile(chromeHevc);
    expect(profile['Name'], 'WonderFlix (browser)');
    expect(transcoding(profile)['VideoCodec'], 'hevc,h264');
    expect(transcoding(profile)['AudioCodec'], 'aac');
    expect(transcoding(profile)['Container'], 'mp4');
    expect(transcoding(profile)['Protocol'], 'hls');
    expect(directContainers(profile), contains('mkv'));
    final mp4 = (profile['DirectPlayProfiles'] as List).cast<Map>().first;
    expect(mp4['Container'], 'mp4,m4v');
    expect(mp4['VideoCodec'], contains('hevc'));
  });

  test('chromeNoHevc: video convertito in H.264', () {
    final profile = buildBrowserDeviceProfile(chromeNoHevc);
    expect(transcoding(profile)['VideoCodec'], 'h264');
  });

  test('edge: AC3 e EAC3 copiati', () {
    final profile = buildBrowserDeviceProfile(edge);
    expect(transcoding(profile)['AudioCodec'], 'aac,ac3,eac3');
  });

  test('firefox: niente mkv nel direct play', () {
    final profile = buildBrowserDeviceProfile(firefox);
    expect(directContainers(profile), isNot(contains('mkv')));
  });

  test('tutti: sottotitoli e audio secondario', () {
    for (final caps in [chromeHevc, chromeNoHevc, edge, firefox]) {
      final profile = buildBrowserDeviceProfile(caps, maxBitrate: 1234);
      expect(subtitleMethod(profile, 'pgssub'), 'External');
      expect(subtitleMethod(profile, 'ass'), 'External');
      expect(subtitleMethod(profile, 'dvbsub'), 'Encode');
      expect(profile['MaxStreamingBitrate'], 1234);
      expect(profile['MaxStaticBitrate'], 1234);
      expect(profile['CodecProfiles'], contains(predicate<Map>((p) =>
          p['Type'] == 'VideoAudio' &&
          (p['Conditions'] as List).cast<Map>().any(
              (c) => c['Property'] == 'IsSecondaryAudio'))));
    }
  });

  test('HEVC senza Main10: limite a 8 bit', () {
    final profile = buildBrowserDeviceProfile(const BrowserCapabilities(
      h264: true,
      hevc: true,
      hevcMain10: false,
      vp9: false,
      av1: false,
      aac: true,
      mp3: false,
      opus: false,
      flac: false,
      ac3: false,
      eac3: false,
      mkv: false,
      fmp4Hls: true,
      nativeHls: false,
      isFirefox: false,
    ));
    final hevc = (profile['CodecProfiles'] as List)
        .cast<Map>()
        .singleWhere((p) => p['Codec'] == 'hevc');
    final conditions = (hevc['Conditions'] as List).cast<Map>();
    expect(conditions.singleWhere((c) => c['Property'] == 'VideoProfile')['Value'],
        'main');
    expect(conditions.singleWhere((c) => c['Property'] == 'VideoBitDepth')['Value'],
        '8');
  });

  group('capConvertedVideo', () {
    test('solo audio convertito: URL invariato', () {
      const url =
          '/videos/m1/master.m3u8?MediaSourceId=ms1&TranscodeReasons=AudioCodecNotSupported';
      expect(capConvertedVideo(url), url);
    });

    test('video convertito: 1080p e 20 Mbps', () {
      final url = Uri.parse(capConvertedVideo(
          '/videos/m1/master.m3u8?TranscodeReasons=VideoCodecNotSupported%2CAudioCodecNotSupported&VideoBitrate=200000000'));
      expect(url.queryParameters['MaxHeight'], '1080');
      expect(url.queryParameters['VideoBitrate'], '20000000');
      expect(url.queryParameters['TranscodeReasons'],
          'VideoCodecNotSupported,AudioCodecNotSupported');
    });

    test('MaxHeight già più basso: resta', () {
      final url = Uri.parse(capConvertedVideo(
          '/videos/m1/master.m3u8?MaxHeight=720&TranscodeReasons=VideoBitDepthNotSupported'));
      expect(url.queryParameters['MaxHeight'], '720');
    });
  });
}
