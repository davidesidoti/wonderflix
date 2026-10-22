/// Profilo del dispositivo inviato a `PlaybackInfo`.
library;

/// Limite di bitrate per la qualità "Originale": abbastanza alto da non
/// forzare mai la transcodifica dei file originali.
const originalQualityBitrate = 200000000;

/// Sottotitoli testuali: in direct play si leggono dal file, in
/// transcodifica il server li consegna come file separati.
const textSubtitleFormats = [
  'srt',
  'subrip',
  'ass',
  'ssa',
  'vtt',
  'webvtt',
  'sub',
  'mov_text',
];

/// Sottotitoli grafici: in direct play si leggono dal file, in transcodifica
/// il server li brucia nel video.
const imageSubtitleFormats = ['pgssub', 'pgs', 'dvdsub', 'dvbsub', 'vobsub'];

/// Formati che il server può consegnare come file separato.
const externalSubtitleFormats = ['srt', 'ass', 'ssa', 'vtt', 'sub'];

/// mpv riproduce qualunque contenitore e codec, quindi il direct play non ha
/// limiti: un profilo senza contenitore né codec vale per tutti. La
/// transcodifica, usata solo come ripiego, produce HLS H.264.
///
/// Sottotitoli:
/// - `Embed` per tutti: in direct play le tracce del file restano nel file;
/// - `External` per i testuali: i file esterni, e in transcodifica quelli
///   estratti dal server, si scaricano a parte;
/// - in transcodifica i grafici non hanno un profilo esterno, quindi il
///   server li brucia nel video.
Map<String, dynamic> buildDeviceProfile(
        {int maxBitrate = originalQualityBitrate}) =>
    {
      'Name': 'WonderFlix (mpv)',
      'MaxStreamingBitrate': maxBitrate,
      'MaxStaticBitrate': maxBitrate,
      'DirectPlayProfiles': [
        {'Type': 'Video'},
        {'Type': 'Audio'},
      ],
      'TranscodingProfiles': [
        {
          'Type': 'Video',
          'Container': 'ts',
          'Protocol': 'hls',
          'Context': 'Streaming',
          'VideoCodec': 'h264',
          'AudioCodec': 'aac,mp3,ac3,eac3',
          'MaxAudioChannels': '6',
          'MinSegments': 1,
          'BreakOnNonKeyFrames': true,
        },
      ],
      'ContainerProfiles': <Object>[],
      'CodecProfiles': <Object>[],
      'SubtitleProfiles': [
        for (final format in [...textSubtitleFormats, ...imageSubtitleFormats])
          {'Format': format, 'Method': 'Embed'},
        for (final format in externalSubtitleFormats)
          {'Format': format, 'Method': 'External'},
      ],
    };
