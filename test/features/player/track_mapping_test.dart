import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/features/player/track_mapping.dart';

void main() {
  const tracks = [
    EngineTrack(id: '1', type: EngineTrackType.video, ffIndex: 0),
    EngineTrack(id: '1', type: EngineTrackType.audio, ffIndex: 1),
    EngineTrack(id: '2', type: EngineTrackType.audio, ffIndex: 2),
    EngineTrack(id: '1', type: EngineTrackType.subtitle, ffIndex: 3),
    EngineTrack(
        id: '2', type: EngineTrackType.subtitle, ffIndex: 5, external: true),
  ];

  test('Index di Jellyfin = ff-index di mpv', () {
    expect(
        engineTrackFor(
                const MediaStreamInfo(index: 2, kind: StreamKind.audio), tracks)
            ?.id,
        '2');
    expect(
        engineTrackFor(
                const MediaStreamInfo(index: 3, kind: StreamKind.subtitle),
                tracks)
            ?.id,
        '1');
  });

  test('il tipo deve coincidere', () {
    expect(
        engineTrackFor(
            const MediaStreamInfo(index: 1, kind: StreamKind.subtitle), tracks),
        isNull);
  });

  test('le tracce esterne di mpv non si confrontano con gli indici del file',
      () {
    expect(
        engineTrackFor(
            const MediaStreamInfo(index: 5, kind: StreamKind.subtitle), tracks),
        isNull);
  });

  test('stream senza traccia corrispondente', () {
    expect(
        engineTrackFor(
            const MediaStreamInfo(index: 9, kind: StreamKind.audio), tracks),
        isNull);
    expect(
        engineTrackFor(
            const MediaStreamInfo(index: 0, kind: StreamKind.other), tracks),
        isNull);
  });
}
