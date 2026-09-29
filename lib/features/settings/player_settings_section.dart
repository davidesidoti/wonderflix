import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../player/player_settings.dart';

String qualityLabel(AppLocalizations l, StreamQuality quality) =>
    quality == StreamQuality.original
        ? l.settingsQualityOriginal
        : l.settingsQualityMbps(quality.bitrate ~/ 1000000);

/// Impostazioni del player salvate su questo PC.
class PlayerSettingsSection extends ConsumerWidget {
  const PlayerSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(playerSettingsProvider);
    void save(PlayerSettings next) =>
        unawaited(ref.read(playerSettingsProvider.notifier).update(next));

    final scaleLabels = {
      0.8: l.settingsSubtitleSmall,
      1.0: l.settingsSubtitleNormal,
      1.25: l.settingsSubtitleLarge,
      1.5: l.settingsSubtitleHuge,
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsPlayerHint,
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(height: 16),
          Text(l.settingsQuality),
          const SizedBox(height: 6),
          DropdownButton<StreamQuality>(
            key: const Key('player-quality'),
            value: settings.quality,
            items: [
              for (final quality in StreamQuality.values)
                DropdownMenuItem(
                    value: quality, child: Text(qualityLabel(l, quality))),
            ],
            onChanged: (quality) {
              if (quality != null) save(settings.copyWith(quality: quality));
            },
          ),
          const SizedBox(height: 16),
          Text(l.settingsSubtitleSize),
          const SizedBox(height: 6),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: [
              for (final scale in subtitleScaleOptions)
                ButtonSegment(value: scale, label: Text(scaleLabels[scale]!)),
            ],
            selected: {settings.subtitleScale},
            onSelectionChanged: (selection) =>
                save(settings.copyWith(subtitleScale: selection.first)),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsHardwareDecoding),
            value: settings.hardwareDecoding,
            onChanged: (value) =>
                save(settings.copyWith(hardwareDecoding: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsAutoSkipIntro),
            value: settings.autoSkipIntro,
            onChanged: (value) => save(settings.copyWith(autoSkipIntro: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsAutoplayNext),
            value: settings.autoplayNext,
            onChanged: (value) => save(settings.copyWith(autoplayNext: value)),
          ),
        ],
      ),
    );
  }
}
