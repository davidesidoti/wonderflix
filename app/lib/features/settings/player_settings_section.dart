import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../admin/admin_kit.dart';
import '../player/player_settings.dart';
import 'settings_kit.dart';

/// "Massima (originale)", "Alta (20 Mbps)", "Media (8 Mbps)", "Bassa (4 Mbps)".
String qualityLabel(AppLocalizations l, StreamQuality quality) {
  final mbps = quality.bitrate ~/ 1000000;
  return switch (quality) {
    StreamQuality.original => l.settingsQualityOriginal,
    StreamQuality.mbps20 => l.settingsQualityHigh(mbps),
    StreamQuality.mbps8 => l.settingsQualityMedium(mbps),
    StreamQuality.mbps4 => l.settingsQualityLow(mbps),
  };
}

/// Riproduzione: qualità, prossimo episodio, salta intro, decodifica. Salvate
/// su questo PC.
class PlayerSettingsSection extends ConsumerWidget {
  const PlayerSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(playerSettingsProvider);
    void save(PlayerSettings next) =>
        unawaited(ref.read(playerSettingsProvider.notifier).update(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminList(
          children: [
            SettingsRow(
              label: l.settingsQuality,
              hint: l.settingsQualityHint,
              wideTrailing: true,
              trailing: SettingsDropdown<StreamQuality>(
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
            ),
            SettingsSwitchRow(
              label: l.settingsAutoplayNext,
              value: settings.autoplayNext,
              onChanged: (value) => save(settings.copyWith(autoplayNext: value)),
            ),
            SettingsSwitchRow(
              label: l.settingsAutoSkipIntro,
              value: settings.autoSkipIntro,
              onChanged: (value) =>
                  save(settings.copyWith(autoSkipIntro: value)),
            ),
            // Nel browser la decodifica la sceglie il browser.
            if (!kIsWeb)
              SettingsSwitchRow(
                label: l.settingsHardwareDecoding,
                hint: l.settingsHardwareDecodingHint,
                value: settings.hardwareDecoding,
                onChanged: (value) =>
                    save(settings.copyWith(hardwareDecoding: value)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(l.settingsPlayerHint,
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
      ],
    );
  }
}
