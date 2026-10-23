/// Profilo del dispositivo per il player del browser, sulle regole di
/// `browserDeviceProfile.js` di jellyfin-web. Puro Dart: le prove del
/// browser arrivano già fatte in [BrowserCapabilities] (vedi
/// `browser_probe.dart`).
library;

import 'device_profile.dart';

/// Cosa il browser dichiara di saper leggere.
class BrowserCapabilities {
  const BrowserCapabilities({
    required this.h264,
    required this.hevc,
    required this.hevcMain10,
    required this.vp9,
    required this.av1,
    required this.aac,
    required this.mp3,
    required this.opus,
    required this.flac,
    required this.ac3,
    required this.eac3,
    required this.mkv,
    required this.fmp4Hls,
    required this.nativeHls,
    required this.isFirefox,
  });

  final bool h264;
  final bool hevc;
  final bool hevcMain10;
  final bool vp9;
  final bool av1;
  final bool aac;
  final bool mp3;
  final bool opus;
  final bool flac;
  final bool ac3;
  final bool eac3;
  final bool mkv;

  /// HLS con segmenti fMP4 (altrimenti TS).
  final bool fmp4Hls;

  /// Il browser legge l'HLS da solo (Safari), senza MediaSource.
  final bool nativeHls;
  final bool isFirefox;

  /// Le capacità presenti, per il log.
  @override
  String toString() => {
        'h264': h264,
        'hevc': hevc,
        'hevcMain10': hevcMain10,
        'vp9': vp9,
        'av1': av1,
        'aac': aac,
        'mp3': mp3,
        'opus': opus,
        'flac': flac,
        'ac3': ac3,
        'eac3': eac3,
        'mkv': mkv,
        'fmp4Hls': fmp4Hls,
        'nativeHls': nativeHls,
        'firefox': isFirefox,
      }.entries.where((e) => e.value).map((e) => e.key).join(' ');
}

/// Profilo per `PlaybackInfo` dal browser:
/// - direct play solo con contenitori e codec letti dal browser;
/// - transcodifica HLS che copia il video quando il browser lo legge
///   (HEVC solo in fMP4), altrimenti lo converte in H.264;
/// - sottotitoli `External` dove il player li sa mostrare, gli altri bruciati.
Map<String, dynamic> buildBrowserDeviceProfile(BrowserCapabilities caps,
    {int maxBitrate = originalQualityBitrate}) {
  String codecs(Map<String, bool> all) =>
      all.entries.where((e) => e.value).map((e) => e.key).join(',');
  final video = codecs(
      {'h264': caps.h264, 'hevc': caps.hevc, 'vp9': caps.vp9, 'av1': caps.av1});
  final audio = codecs({
    'aac': caps.aac,
    'mp3': caps.mp3,
    'opus': caps.opus,
    'flac': caps.flac,
    'ac3': caps.ac3,
    'eac3': caps.eac3,
  });
  final webmVideo = codecs({'vp9': caps.vp9, 'av1': caps.av1});
  return {
    'Name': 'WonderFlix (browser)',
    'MaxStreamingBitrate': maxBitrate,
    'MaxStaticBitrate': maxBitrate,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': 'mp4,m4v',
        'VideoCodec': video,
        'AudioCodec': audio,
      },
      if (webmVideo.isNotEmpty)
        {
          'Type': 'Video',
          'Container': 'webm',
          'VideoCodec': webmVideo,
          'AudioCodec': codecs({'opus': caps.opus}),
        },
      if (caps.mkv)
        {
          'Type': 'Video',
          'Container': 'mkv',
          'VideoCodec': video,
          'AudioCodec': audio,
        },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': caps.fmp4Hls ? 'mp4' : 'ts',
        'Protocol': 'hls',
        'Context': 'Streaming',
        // L'HEVC in HLS solo con segmenti fMP4, come jellyfin-web.
        'VideoCodec': caps.hevc && caps.fmp4Hls ? 'hevc,h264' : 'h264',
        'AudioCodec': codecs({'aac': true, 'ac3': caps.ac3, 'eac3': caps.eac3}),
        'MaxAudioChannels': '6',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
    ],
    'ContainerProfiles': <Object>[],
    'CodecProfiles': [
      // Il player non cambia traccia audio da solo: solo la principale.
      {
        'Type': 'VideoAudio',
        'Conditions': [
          {
            'Condition': 'Equals',
            'Property': 'IsSecondaryAudio',
            'Value': 'false',
            'IsRequired': false,
          },
        ],
      },
      if (caps.hevc)
        {
          'Type': 'Video',
          'Codec': 'hevc',
          'Conditions': [
            {
              'Condition': 'EqualsAny',
              'Property': 'VideoProfile',
              'Value': caps.hevcMain10 ? 'main|main 10' : 'main',
              'IsRequired': false,
            },
            if (!caps.hevcMain10)
              {
                'Condition': 'LessThanEqual',
                'Property': 'VideoBitDepth',
                'Value': '8',
                'IsRequired': false,
              },
          ],
        },
    ],
    // Senza profilo il server brucia il sottotitolo nel video.
    'SubtitleProfiles': [
      for (final format in const [
        'srt',
        'subrip',
        'vtt',
        'webvtt',
        'ass',
        'ssa',
        'pgssub',
        'dvdsub',
      ])
        {'Format': format, 'Method': 'External'},
      for (final format in const ['dvbsub', 'sub', 'vobsub', 'mov_text'])
        {'Format': format, 'Method': 'Encode'},
    ],
  };
}

/// Motivi di transcodifica per cui il server converte il video (non lo
/// copia).
const _videoConversionReasons = {
  'VideoCodecNotSupported',
  'VideoProfileNotSupported',
  'VideoLevelNotSupported',
  'VideoBitDepthNotSupported',
  'VideoRangeTypeNotSupported',
  'VideoCodecTagNotSupported',
  'VideoResolutionNotSupported',
  'VideoBitrateNotSupported',
  'VideoFramerateNotSupported',
  'RefFramesNotSupported',
  'AnamorphicVideoNotSupported',
  'InterlacedVideoNotSupported',
  'SubtitleCodecNotSupported',
};

/// Tetto di 1080p e 20 Mbps al video che il server converte. Un video
/// copiato (es. 4K HEVC con solo l'audio convertito) resta com'è.
String capConvertedVideo(String transcodingUrl) {
  final uri = Uri.parse(transcodingUrl);
  final query = uri.queryParameters;
  final reasons = (query['TranscodeReasons'] ?? '').split(',');
  if (!reasons.any(_videoConversionReasons.contains)) return transcodingUrl;
  String capped(String key, int max) {
    final current = int.tryParse(query[key] ?? '');
    return (current == null || current > max ? max : current).toString();
  }

  return uri.replace(queryParameters: {
    ...query,
    'MaxHeight': capped('MaxHeight', 1080),
    'VideoBitrate': capped('VideoBitrate', 20000000),
  }).toString();
}
