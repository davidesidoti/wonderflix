/// Profilo del dispositivo per Android TV / Fire TV, costruito dai decoder
/// del dispositivo (canale `wonderflix/player`, `decoderCapabilities`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_profile.dart';

/// Decoder video hardware di un codec, uniti tra tutti quelli dello stesso mime.
class VideoDecoderCaps {
  const VideoDecoderCaps({
    required this.mime,
    required this.maxWidth,
    required this.maxHeight,
    required this.tenBit,
  });

  final String mime;
  final int maxWidth;
  final int maxHeight;
  final bool tenBit;

  @override
  String toString() => '$mime ${maxWidth}x$maxHeight${tenBit ? ' 10bit' : ''}';
}

/// Cosa il dispositivo sa decodificare.
class DecoderCaps {
  const DecoderCaps({
    required this.video,
    required this.audioMimes,
    required this.hdrTypes,
  });

  /// Dalla risposta del canale. Lo stesso mime può comparire più volte
  /// (più decoder): si tengono le dimensioni massime e il 10 bit se uno lo ha.
  factory DecoderCaps.fromMap(Map map) {
    final merged = <String, VideoDecoderCaps>{};
    for (final entry in (map['video'] as List? ?? const [])) {
      final m = entry as Map;
      final mime = m['mime'] as String;
      final old = merged[mime];
      final width = (m['maxWidth'] as num?)?.toInt() ?? 0;
      final height = (m['maxHeight'] as num?)?.toInt() ?? 0;
      merged[mime] = VideoDecoderCaps(
        mime: mime,
        maxWidth: old != null && old.maxWidth > width ? old.maxWidth : width,
        maxHeight: old != null && old.maxHeight > height
            ? old.maxHeight
            : height,
        tenBit: (old?.tenBit ?? false) || m['tenBit'] == true,
      );
    }
    return DecoderCaps(
      video: merged.values.toList(),
      audioMimes: [for (final a in (map['audio'] as List? ?? const [])) '$a'],
      hdrTypes: [for (final h in (map['hdrTypes'] as List? ?? const [])) '$h'],
    );
  }

  final List<VideoDecoderCaps> video;
  final List<String> audioMimes;
  final List<String> hdrTypes;

  @override
  String toString() =>
      'video: ${video.join(', ')}; audio: ${audioMimes.join(', ')}; '
      'hdr: ${hdrTypes.join(', ')}';
}

/// Le capacità del dispositivo; su Android l'avvio le legge e sovrascrive il
/// provider, altrove resta `null` (profilo di mpv o del browser).
final decoderCapsProvider = Provider<DecoderCaps?>((ref) => null);

const _videoCodecs = {
  'video/avc': 'h264',
  'video/hevc': 'hevc',
  'video/x-vnd.on2.vp9': 'vp9',
  'video/av01': 'av1',
};

const _audioCodecs = {
  'audio/mp4a-latm': 'aac',
  'audio/mpeg': 'mp3',
  'audio/ac3': 'ac3',
  'audio/eac3': 'eac3',
  'audio/vnd.dts': 'dts',
  'audio/flac': 'flac',
  'audio/opus': 'opus',
  'audio/vorbis': 'vorbis',
};

/// Profilo per `PlaybackInfo` su Android TV: direct play solo di ciò che i
/// decoder del dispositivo leggono (con i limiti di risoluzione e di
/// profondità di colore), il resto come `buildDeviceProfile`. L'HDR non
/// limita nulla: senza display HDR il decoder converte in SDR.
Map<String, dynamic> buildAndroidTvDeviceProfile(
  DecoderCaps caps, {
  int maxBitrate = originalQualityBitrate,
}) {
  final video = [
    for (final v in caps.video)
      if (_videoCodecs.containsKey(v.mime)) v,
  ];
  final audio = [
    for (final mime in caps.audioMimes.toSet())
      if (_audioCodecs.containsKey(mime)) _audioCodecs[mime]!,
  ];
  Map<String, Object> condition(String property, int max) => {
    'Condition': 'LessThanEqual',
    'Property': property,
    'Value': '$max',
    'IsRequired': false,
  };
  return {
    'Name': 'WonderFlix (Android TV)',
    'MaxStreamingBitrate': maxBitrate,
    'MaxStaticBitrate': maxBitrate,
    'DirectPlayProfiles': [
      // Una lista vuota per Jellyfin vuol dire "qualunque codec": senza
      // decoder noti niente direct play.
      if (video.isNotEmpty && audio.isNotEmpty)
        {
          'Type': 'Video',
          'Container': 'mkv,webm,mp4,m4v,mov,ts',
          'VideoCodec': [for (final v in video) _videoCodecs[v.mime]].join(','),
          'AudioCodec': audio.join(','),
        },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'Context': 'Streaming',
        // Se serve convertire solo l'audio, il server copia l'HEVC invece di
        // ricodificare in 4K senza GPU; senza decoder HEVC resta H.264.
        'VideoCodec': video.any((v) => v.mime == 'video/hevc')
            ? 'h264,hevc'
            : 'h264',
        'AudioCodec': 'aac,mp3,ac3,eac3',
        'MaxAudioChannels': '6',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
    ],
    'ContainerProfiles': <Object>[],
    'CodecProfiles': [
      for (final v in video)
        {
          'Type': 'Video',
          'Codec': _videoCodecs[v.mime],
          'Conditions': [
            condition('Width', v.maxWidth),
            condition('Height', v.maxHeight),
            // H.264 Hi10P (comune negli anime) non ha decoder hardware.
            if (v.mime == 'video/avc' || (v.mime == 'video/hevc' && !v.tenBit))
              condition('VideoBitDepth', 8),
          ],
        },
    ],
    'SubtitleProfiles': [
      for (final format in [...textSubtitleFormats, ...imageSubtitleFormats])
        {'Format': format, 'Method': 'Embed'},
      for (final format in externalSubtitleFormats)
        {'Format': format, 'Method': 'External'},
    ],
  };
}
