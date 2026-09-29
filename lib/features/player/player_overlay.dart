import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'seek_bar.dart';

/// Controlli in sovrimpressione: in alto indietro e titolo, in basso barra
/// di avanzamento e comandi.
class PlayerOverlay extends StatelessWidget {
  const PlayerOverlay({
    super.key,
    required this.view,
    required this.engine,
    required this.fullscreen,
    required this.onBack,
    required this.onTogglePlay,
    required this.onSeekBy,
    required this.onSeekTo,
    required this.onVolume,
    required this.onToggleMute,
    required this.onToggleTracks,
    required this.onToggleFullscreen,
    this.onNextEpisode,
    this.chapters = const [],
    this.preview,
  });

  final PlayerViewState view;
  final VideoEngine engine;
  final bool fullscreen;
  final VoidCallback onBack;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekBy;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleTracks;
  final VoidCallback onToggleFullscreen;

  /// `null` se non c'è un episodio successivo.
  final VoidCallback? onNextEpisode;
  final List<ChapterMark> chapters;
  final Widget? Function(Duration position)? preview;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = view.item;
    final episode = item != null && item.kind == ItemKind.episode
        ? cardSubtitle(item)
        : null;
    final volume = view.muted ? 0.0 : view.volume;

    return IconButtonTheme(
      data: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: WfColors.cream)),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 24, 48),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      tooltip: l.navBack,
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 8),
                    if (item != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cardTitle(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WfText.display(28)),
                            if (episode != null)
                              Text(episode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: WfColors.creamMuted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xE6000000), Color(0x00000000)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SeekBar(
                      engine: engine,
                      onSeek: onSeekTo,
                      chapters: chapters,
                      preview: preview,
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.rewind),
                          tooltip: l.playerRewind,
                          onPressed: () => onSeekBy(-seekStep),
                        ),
                        IconButton(
                          iconSize: 34,
                          icon: Icon(view.playing
                              ? LucideIcons.pause
                              : LucideIcons.play),
                          tooltip: view.playing ? l.playerPause : l.actionPlay,
                          onPressed: onTogglePlay,
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.fastForward),
                          tooltip: l.playerForward,
                          onPressed: () => onSeekBy(seekStep),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(volume == 0
                              ? LucideIcons.volumeX
                              : LucideIcons.volume2),
                          tooltip:
                              view.muted ? l.playerUnmute : l.playerMute,
                          onPressed: onToggleMute,
                        ),
                        SizedBox(
                          width: 120,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              activeTrackColor: WfColors.cream,
                              inactiveTrackColor:
                                  WfColors.cream.withValues(alpha: 0.2),
                              thumbColor: WfColors.cream,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              key: const Key('volume-slider'),
                              value: volume,
                              max: 100,
                              onChanged: onVolume,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TimeLabel(engine: engine),
                        const Spacer(),
                        if (onNextEpisode != null)
                          IconButton(
                            icon: const Icon(LucideIcons.skipForward),
                            tooltip: l.playerNextEpisode,
                            onPressed: onNextEpisode,
                          ),
                        IconButton(
                          icon: const Icon(LucideIcons.captions),
                          tooltip: l.playerAudioAndSubtitles,
                          onPressed: onToggleTracks,
                        ),
                        IconButton(
                          icon: Icon(fullscreen
                              ? LucideIcons.minimize
                              : LucideIcons.maximize),
                          tooltip: fullscreen
                              ? l.playerExitFullscreen
                              : l.playerFullscreen,
                          onPressed: onToggleFullscreen,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
