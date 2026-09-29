import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/device_profile.dart';
import '../../core/jellyfin/playback_api.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';

/// Come riprodurre un elemento: sorgente, metodo, URL con header e tracce.
class PlaybackPlan {
  const PlaybackPlan({
    required this.itemId,
    required this.method,
    required this.mediaSource,
    required this.playSessionId,
    required this.source,
    this.audioIndex,
    this.subtitleIndex,
  });

  final String itemId;
  final PlayMethod method;
  final MediaSourceInfo mediaSource;
  final String? playSessionId;
  final VideoSource source;

  /// Indici Jellyfin delle tracce da mostrare; `null` = nessuna.
  final int? audioIndex;
  final int? subtitleIndex;

  bool get isTranscode => method == PlayMethod.transcode;

  /// `true` se il sottotitolo [index] viene bruciato nel video dal server
  /// (grafico, in transcodifica): cambiarlo richiede una nuova conversione.
  bool burnsIn(int? index) {
    if (!isTranscode || index == null) return false;
    final stream = mediaSource.stream(index);
    return stream != null && !stream.deliveredExternally;
  }
}

/// Sceglie come riprodurre un elemento: direct play dal file originale
/// quando il server lo consente, altrimenti la transcodifica HLS proposta
/// dal server.
class PlaybackService {
  PlaybackService({
    required PlaybackApi api,
    required Uri serverUrl,
    required String Function() authorization,
    this.breakDirectPlay = false,
  })  : _api = api,
        _serverUrl = serverUrl,
        _authorization = authorization;

  final PlaybackApi _api;
  final Uri _serverUrl;

  /// Header `Authorization` corrente: il token viaggia nell'header, non
  /// nell'URL.
  final String Function() _authorization;

  /// Solo per le prove manuali del ripiego: rende invalido l'URL del direct
  /// play, così l'apertura fallisce.
  final bool breakDirectPlay;

  /// - [forceTranscode]: chiede al server solo la transcodifica (ripiego o
  ///   cambio di traccia in transcodifica).
  /// - Indici `null`: tracce predefinite del server (preferenze dell'utente).
  /// - [subtitleIndex] `-1`: nessun sottotitolo.
  Future<PlaybackPlan> prepare({
    required String itemId,
    required String userId,
    Duration start = Duration.zero,
    bool forceTranscode = false,
    String? mediaSourceId,
    int? audioIndex,
    int? subtitleIndex,
    int maxBitrate = originalQualityBitrate,
  }) async {
    final info = await _api.playbackInfo(
      itemId,
      userId: userId,
      start: start,
      maxBitrate: maxBitrate,
      allowDirect: !forceTranscode,
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioIndex,
      subtitleStreamIndex: subtitleIndex,
    );
    final code = info.errorCode;
    if (code != null) throw PlaybackUnavailableException(code);
    final source = _pickSource(info.mediaSources, mediaSourceId);
    if (source == null) throw const PlaybackUnavailableException(null);

    final String url;
    final PlayMethod method;
    final transcodingUrl = source.transcodingUrl;
    if (!forceTranscode && source.supportsDirectPlay) {
      url = Uri.parse('$_serverUrl/Videos/$itemId/stream').replace(
        queryParameters: {
          'static': 'true',
          'mediaSourceId':
              breakDirectPlay ? 'wonderflix-test-invalid' : source.id,
          'playSessionId': ?info.playSessionId,
        },
      ).toString();
      method = PlayMethod.directPlay;
    } else if (transcodingUrl != null) {
      url = resolveServerUrl(_serverUrl, transcodingUrl);
      method = PlayMethod.transcode;
    } else {
      throw const PlaybackUnavailableException(null);
    }

    int? chosen(int? requested, int? fallback) {
      final value = requested ?? fallback;
      return value == null || value < 0 ? null : value;
    }

    return PlaybackPlan(
      itemId: itemId,
      method: method,
      mediaSource: source,
      playSessionId: info.playSessionId,
      source: VideoSource(
        url: url,
        headers: {'Authorization': _authorization()},
        start: start,
      ),
      audioIndex: chosen(audioIndex, source.defaultAudioStreamIndex),
      subtitleIndex: chosen(subtitleIndex, source.defaultSubtitleStreamIndex),
    );
  }

  /// URL assoluto di un sottotitolo da caricare a parte
  /// (`MediaStreamInfo.deliveredExternally`).
  String subtitleUrl(MediaStreamInfo stream) =>
      resolveServerUrl(_serverUrl, stream.deliveryUrl!);

  static MediaSourceInfo? _pickSource(
      List<MediaSourceInfo> sources, String? id) {
    if (id != null) {
      for (final source in sources) {
        if (source.id == id) return source;
      }
    }
    return sources.firstOrNull;
  }
}
