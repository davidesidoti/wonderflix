import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/playback_api.dart';
import '../../core/video/media_kit_engine.dart';
import '../../core/video/video_engine.dart';
import 'playback_service.dart';
import 'player_window.dart';

final playbackApiProvider =
    Provider<PlaybackApi>((ref) => PlaybackApi(ref.watch(jellyfinHttpProvider)));

final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final http = ref.watch(jellyfinHttpProvider);
  return PlaybackService(
    api: ref.watch(playbackApiProvider),
    serverUrl: ref.watch(appConfigProvider).serverUrl,
    authorization: () => http.authorizationHeader,
    // Solo per provare il ripiego: --dart-define=wfBreakDirectPlay=true
    breakDirectPlay: const bool.fromEnvironment('wfBreakDirectPlay'),
  );
});

/// Crea un motore video per ogni riproduzione; nei test si usa un motore finto.
final videoEngineFactoryProvider =
    Provider<VideoEngine Function()>((ref) => MediaKitEngine.new);

final playerWindowProvider =
    Provider<PlayerWindow>((ref) => WindowManagerPlayerWindow());
