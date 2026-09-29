/// Modelli della riproduzione (sottoinsieme di `PlaybackInfoResponse` e dei
/// report `Sessions/Playing*`).
library;

import 'item_models.dart';

/// Come viene riprodotto un elemento (valore `PlayMethod` dell'API).
enum PlayMethod {
  directPlay('DirectPlay'),
  transcode('Transcode');

  const PlayMethod(this.apiName);

  final String apiName;
}

enum StreamKind { video, audio, subtitle, other }

int? _int(Object? value) => (value as num?)?.toInt();

/// Una traccia del file (`MediaStream`).
class MediaStreamInfo {
  const MediaStreamInfo({
    required this.index,
    required this.kind,
    this.codec,
    this.language,
    this.title,
    this.displayTitle,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.isTextSubtitle = false,
    this.deliveryMethod,
    this.deliveryUrl,
  });

  factory MediaStreamInfo.fromJson(Map<String, dynamic> json) =>
      MediaStreamInfo(
        index: _int(json['Index']) ?? -1,
        kind: switch (json['Type']) {
          'Video' => StreamKind.video,
          'Audio' => StreamKind.audio,
          'Subtitle' => StreamKind.subtitle,
          _ => StreamKind.other,
        },
        codec: json['Codec'] as String?,
        language: json['Language'] as String?,
        title: json['Title'] as String?,
        displayTitle: json['DisplayTitle'] as String?,
        isDefault: json['IsDefault'] as bool? ?? false,
        isForced: json['IsForced'] as bool? ?? false,
        isExternal: json['IsExternal'] as bool? ?? false,
        isTextSubtitle: json['IsTextSubtitleStream'] as bool? ?? false,
        deliveryMethod: json['DeliveryMethod'] as String?,
        deliveryUrl: json['DeliveryUrl'] as String?,
      );

  /// `Index` di Jellyfin: per le tracce interne coincide con `ff-index` di mpv.
  final int index;
  final StreamKind kind;
  final String? codec;
  final String? language;
  final String? title;

  /// Nome già pronto per i menu (es. "Italiano - AC3 - 5.1 - Predefinito").
  final String? displayTitle;
  final bool isDefault;
  final bool isForced;

  /// File di sottotitoli separato, accanto al video.
  final bool isExternal;
  final bool isTextSubtitle;

  /// `Embed`, `External`, `Encode` (bruciato nel video), `Hls`, `Drop`.
  final String? deliveryMethod;

  /// Percorso (di solito relativo al server) da cui scaricare il sottotitolo.
  final String? deliveryUrl;

  /// Sottotitolo da caricare a parte: file esterno, oppure estratto dal
  /// server durante la transcodifica.
  bool get deliveredExternally =>
      deliveryMethod == 'External' && (deliveryUrl?.isNotEmpty ?? false);
}

/// Una sorgente riproducibile dell'elemento (`MediaSourceInfo`).
class MediaSourceInfo {
  const MediaSourceInfo({
    required this.id,
    this.supportsDirectPlay = false,
    this.transcodingUrl,
    this.defaultAudioStreamIndex,
    this.defaultSubtitleStreamIndex,
    this.streams = const [],
  });

  factory MediaSourceInfo.fromJson(Map<String, dynamic> json) =>
      MediaSourceInfo(
        id: json['Id'] as String,
        supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? false,
        transcodingUrl: json['TranscodingUrl'] as String?,
        defaultAudioStreamIndex: _int(json['DefaultAudioStreamIndex']),
        defaultSubtitleStreamIndex: _int(json['DefaultSubtitleStreamIndex']),
        streams: (json['MediaStreams'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaStreamInfo.fromJson)
            .toList(),
      );

  final String id;
  final bool supportsDirectPlay;

  /// URL HLS (relativo al server) proposto quando serve la transcodifica.
  final String? transcodingUrl;

  /// Tracce scelte dal server secondo le preferenze dell'utente.
  /// `-1` = nessun sottotitolo.
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;
  final List<MediaStreamInfo> streams;

  List<MediaStreamInfo> get audioStreams =>
      [for (final s in streams) if (s.kind == StreamKind.audio) s];

  List<MediaStreamInfo> get subtitleStreams =>
      [for (final s in streams) if (s.kind == StreamKind.subtitle) s];

  MediaStreamInfo? stream(int index) {
    for (final s in streams) {
      if (s.index == index) return s;
    }
    return null;
  }
}

/// Risposta di `POST /Items/{id}/PlaybackInfo`.
class PlaybackInfoResult {
  const PlaybackInfoResult({
    required this.mediaSources,
    this.playSessionId,
    this.errorCode,
  });

  factory PlaybackInfoResult.fromJson(Map<String, dynamic> json) =>
      PlaybackInfoResult(
        mediaSources: (json['MediaSources'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaSourceInfo.fromJson)
            .toList(),
        playSessionId: json['PlaySessionId'] as String?,
        errorCode: json['ErrorCode'] as String?,
      );

  final List<MediaSourceInfo> mediaSources;
  final String? playSessionId;

  /// `NotAllowed`, `NoCompatibleStream`, `RateLimitExceeded`; `null` se va
  /// tutto bene.
  final String? errorCode;
}

/// Stato della riproduzione da inviare a Jellyfin.
class PlaybackReport {
  const PlaybackReport({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.position,
    required this.isPaused,
    required this.isMuted,
    required this.volume,
    required this.audioStreamIndex,
    required this.subtitleStreamIndex,
    required this.playMethod,
  });

  final String itemId;
  final String mediaSourceId;
  final String? playSessionId;
  final Duration position;
  final bool isPaused;
  final bool isMuted;

  /// 0–100.
  final int volume;
  final int? audioStreamIndex;

  /// `null` = nessun sottotitolo (inviato come `-1`).
  final int? subtitleStreamIndex;
  final PlayMethod playMethod;

  /// Corpo di `Sessions/Playing` e `Sessions/Playing/Progress`.
  Map<String, dynamic> toJson() => {
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PlaySessionId': ?playSessionId,
        'PositionTicks': durationToTicks(position),
        'IsPaused': isPaused,
        'IsMuted': isMuted,
        'VolumeLevel': volume,
        'AudioStreamIndex': ?audioStreamIndex,
        'SubtitleStreamIndex': subtitleStreamIndex ?? -1,
        'PlayMethod': playMethod.apiName,
        'CanSeek': true,
      };

  /// Corpo di `Sessions/Playing/Stopped`.
  Map<String, dynamic> toStoppedJson() => {
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PlaySessionId': ?playSessionId,
        'PositionTicks': durationToTicks(position),
        'Failed': false,
      };
}

/// URL assoluto per un percorso restituito dal server (`TranscodingUrl`,
/// `DeliveryUrl`). I percorsi relativi vanno sotto l'indirizzo del server,
/// compreso l'eventuale sotto-percorso (es. `/jellyfin`): per questo non si
/// usa `Uri.resolve`, che lo perderebbe.
String resolveServerUrl(Uri serverUrl, String url) {
  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasScheme) return url;
  final base = serverUrl.toString().replaceAll(RegExp(r'/+$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}
