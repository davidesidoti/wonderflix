/// Le informazioni tecniche di un titolo (spec R §7.4): le versioni del file
/// e le loro tracce, da `MediaSources` di `GET /Items/{id}`. `JellyfinItem`
/// non le ha.
class ItemMediaInfo {
  const ItemMediaInfo({this.versions = const []});

  factory ItemMediaInfo.fromItemJson(Map<String, dynamic> json) {
    final sources = json['MediaSources'];
    return ItemMediaInfo(versions: [
      if (sources is List)
        for (final source in sources)
          if (source is Map) MediaVersion._fromJson(source),
    ]);
  }

  final List<MediaVersion> versions;
}

/// Una versione del file (`MediaSourceInfo`).
class MediaVersion {
  const MediaVersion({
    required this.id,
    this.name,
    this.container,
    this.fileName,
    this.size,
    this.bitrate,
    this.duration,
    this.video,
    this.audio = const [],
    this.subtitles = const [],
  });

  factory MediaVersion._fromJson(Map<dynamic, dynamic> json) {
    final streams = [
      if (json['MediaStreams'] case final List list)
        for (final stream in list)
          if (stream is Map) stream,
    ];
    final video = streams.where((s) => s['Type'] == 'Video').firstOrNull;
    final ticks = (json['RunTimeTicks'] as num?)?.toInt();
    return MediaVersion(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String?,
      container: json['Container'] as String?,
      fileName: _fileName(json['Path']),
      size: (json['Size'] as num?)?.toInt(),
      bitrate: (json['Bitrate'] as num?)?.toInt(),
      duration: ticks == null
          ? null
          : Duration(microseconds: ticks ~/ _ticksPerMicrosecond),
      video: video == null ? null : VideoTrack._fromJson(video),
      audio: [
        for (final s in streams)
          if (s['Type'] == 'Audio') AudioTrack._fromJson(s),
      ],
      subtitles: [
        for (final s in streams)
          if (s['Type'] == 'Subtitle') SubtitleTrack._fromJson(s),
      ],
    );
  }

  final String id;
  final String? name;
  final String? container;

  /// Solo il nome del file, mai il percorso sul server.
  final String? fileName;
  final int? size;
  final int? bitrate;
  final Duration? duration;
  final VideoTrack? video;
  final List<AudioTrack> audio;
  final List<SubtitleTrack> subtitles;
}

/// Jellyfin conta il tempo in tick da 100 ns.
const _ticksPerMicrosecond = 10;

/// L'ultimo componente di [path], con `/` o `\`; `null` se manca o è vuoto.
String? _fileName(Object? path) {
  if (path is! String) return null;
  final name = path.split(RegExp(r'[/\\]')).last;
  return name.isEmpty ? null : name;
}

class VideoTrack {
  const VideoTrack({this.codec, this.range, this.width, this.height, this.fps});

  factory VideoTrack._fromJson(Map<dynamic, dynamic> json) => VideoTrack(
        codec: json['Codec'] as String?,
        range: json['VideoRange'] as String?,
        width: (json['Width'] as num?)?.toInt(),
        height: (json['Height'] as num?)?.toInt(),
        fps: (json['RealFrameRate'] as num?)?.toDouble(),
      );

  final String? codec;

  /// `SDR` o `HDR`.
  final String? range;
  final int? width;
  final int? height;
  final double? fps;
}

class AudioTrack {
  const AudioTrack({
    required this.index,
    this.language,
    this.codec,
    this.title,
    this.channels,
    this.isDefault = false,
  });

  factory AudioTrack._fromJson(Map<dynamic, dynamic> json) => AudioTrack(
        index: (json['Index'] as num?)?.toInt() ?? -1,
        language: json['Language'] as String?,
        codec: json['Codec'] as String?,
        title: json['Title'] as String?,
        channels: (json['Channels'] as num?)?.toInt(),
        isDefault: json['IsDefault'] == true,
      );

  final int index;
  final String? language;
  final String? codec;
  final String? title;
  final int? channels;
  final bool isDefault;
}

class SubtitleTrack {
  const SubtitleTrack({
    required this.index,
    this.language,
    this.codec,
    this.title,
    this.isExternal = false,
    this.isForced = false,
    this.isHearingImpaired = false,
  });

  factory SubtitleTrack._fromJson(Map<dynamic, dynamic> json) => SubtitleTrack(
        index: (json['Index'] as num?)?.toInt() ?? -1,
        language: json['Language'] as String?,
        codec: json['Codec'] as String?,
        title: json['Title'] as String?,
        isExternal: json['IsExternal'] == true,
        isForced: json['IsForced'] == true,
        isHearingImpaired: json['IsHearingImpaired'] == true,
      );

  final int index;
  final String? language;
  final String? codec;
  final String? title;
  final bool isExternal;
  final bool isForced;
  final bool isHearingImpaired;
}

/// Gli indici delle tracce di sottotitoli esterne di tutte le versioni.
Set<int> externalSubtitleIndexes(ItemMediaInfo info) => {
      for (final version in info.versions)
        for (final track in version.subtitles)
          if (track.isExternal) track.index,
    };
