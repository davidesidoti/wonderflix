import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';

/// Traccia del motore che corrisponde allo stream Jellyfin [stream] di un
/// file in direct play: l'`Index` di Jellyfin è l'`ff-index` di mpv. Le
/// tracce esterne del motore non vengono mai scelte, perché i loro indici
/// non sono quelli del file.
EngineTrack? engineTrackFor(MediaStreamInfo stream, List<EngineTrack> tracks) {
  final type = switch (stream.kind) {
    StreamKind.audio => EngineTrackType.audio,
    StreamKind.subtitle => EngineTrackType.subtitle,
    StreamKind.video => EngineTrackType.video,
    StreamKind.other => null,
  };
  if (type == null) return null;
  for (final track in tracks) {
    if (track.type == type && !track.external && track.ffIndex == stream.index) {
      return track;
    }
  }
  return null;
}
