import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'player_commands.dart';

/// Nome di una traccia nei menu: quello preparato dal server, se c'è.
String trackLabel(AppLocalizations l, MediaStreamInfo stream) =>
    stream.displayTitle ??
    stream.title ??
    stream.language ??
    l.playerTrack(stream.index);

/// "+0,3 s", "0,0 s", "-1,2 s".
String formatSubtitleDelay(Duration delay, String decimalSeparator) {
  final tenths = (delay.inMilliseconds / 100).round();
  final sign = tenths > 0 ? '+' : (tenths < 0 ? '-' : '');
  final value = tenths.abs();
  return '$sign${value ~/ 10}$decimalSeparator${value % 10} s';
}

/// Pannello "Audio e sottotitoli": tracce audio, sottotitoli e ritardo.
class TracksPanel extends StatelessWidget {
  const TracksPanel({
    super.key,
    required this.audio,
    required this.subtitles,
    required this.audioIndex,
    required this.subtitleIndex,
    required this.subtitleDelay,
    required this.onAudio,
    required this.onSubtitle,
    required this.onDelayStep,
  });

  final List<MediaStreamInfo> audio;
  final List<MediaStreamInfo> subtitles;
  final int? audioIndex;
  final int? subtitleIndex;
  final Duration subtitleDelay;
  final ValueChanged<int> onAudio;

  /// `null` = nessun sottotitolo.
  final ValueChanged<int?> onSubtitle;
  final ValueChanged<Duration> onDelayStep;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: WfColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 380),
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Section(
                title: l.playerAudio,
                children: [
                  for (final stream in audio)
                    _TrackTile(
                      label: trackLabel(l, stream),
                      selected: stream.index == audioIndex,
                      onTap: () => onAudio(stream.index),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: _Section(
                      title: l.playerSubtitles,
                      children: [
                        _TrackTile(
                          label: l.playerSubtitlesOff,
                          selected: subtitleIndex == null,
                          onTap: () => onSubtitle(null),
                        ),
                        for (final stream in subtitles)
                          _TrackTile(
                            label: trackLabel(l, stream),
                            selected: stream.index == subtitleIndex,
                            onTap: () => onSubtitle(stream.index),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(l.playerSubtitleDelay,
                            style: const TextStyle(color: WfColors.creamMuted)),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.minus, size: 18),
                        tooltip: l.playerSubtitlesEarlier,
                        onPressed: () => onDelayStep(-subtitleDelayStep),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          formatSubtitleDelay(subtitleDelay, l.decimalSeparator),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.plus, size: 18),
                        tooltip: l.playerSubtitlesLater,
                        onPressed: () => onDelayStep(subtitleDelayStep),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: WfText.display(22, color: WfColors.gold)),
          const SizedBox(height: 8),
          Flexible(child: ListView(shrinkWrap: true, children: children)),
        ],
      );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: selected
                    ? const Icon(LucideIcons.check,
                        size: 16, color: WfColors.gold)
                    : null,
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? WfColors.cream : WfColors.creamMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
