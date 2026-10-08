import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/device_profile.dart';
import '../../l10n/gen/app_localizations.dart';
import '../profiles/profile_preferences.dart';

/// Qualità massima dello streaming. Sotto il bitrate del file il server
/// converte il video.
enum StreamQuality {
  original(originalQualityBitrate),
  mbps20(20000000),
  mbps8(8000000),
  mbps4(4000000);

  const StreamQuality(this.bitrate);

  final int bitrate;
}

/// Dimensioni dei sottotitoli proposte (scala di mpv `sub-scale`).
const subtitleScaleOptions = [0.45, 0.6, 0.8, 1.0, 1.25];

/// Nome di una dimensione dei sottotitoli (Impostazioni e pannello del
/// player).
String subtitleScaleLabel(AppLocalizations l, double scale) => switch (scale) {
      0.45 => l.settingsSubtitleTiny,
      0.6 => l.settingsSubtitleSmall,
      1.0 => l.settingsSubtitleLarge,
      1.25 => l.settingsSubtitleHuge,
      _ => l.settingsSubtitleNormal,
    };

/// Preferenze del player: qualità e decodifica del PC, il resto del profilo
/// (spec K §9.6).
class PlayerSettings {
  const PlayerSettings({
    this.quality = StreamQuality.original,
    this.hardwareDecoding = true,
    this.subtitleScale = 0.8,
    this.autoSkipIntro = false,
    this.autoplayNext = true,
  });

  final StreamQuality quality;
  final bool hardwareDecoding;
  final double subtitleScale;
  final bool autoSkipIntro;
  final bool autoplayNext;

  PlayerSettings copyWith({
    StreamQuality? quality,
    bool? hardwareDecoding,
    double? subtitleScale,
    bool? autoSkipIntro,
    bool? autoplayNext,
  }) =>
      PlayerSettings(
        quality: quality ?? this.quality,
        hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
        subtitleScale: subtitleScale ?? this.subtitleScale,
        autoSkipIntro: autoSkipIntro ?? this.autoSkipIntro,
        autoplayNext: autoplayNext ?? this.autoplayNext,
      );
}

class PlayerSettingsController extends Notifier<PlayerSettings> {
  static const _quality = 'player.quality';
  static const _hardwareDecoding = 'player.hardwareDecoding';
  static const _subtitleScale = 'player.subtitleScale';
  static const _autoSkipIntro = 'player.autoSkipIntro';
  static const _autoplayNext = 'player.autoplayNext';

  @override
  PlayerSettings build() {
    // Qualità e decodifica sono del PC; il resto è del profilo (spec K §9.6).
    final prefs = ref.watch(sharedPreferencesProvider);
    final profile = ref.watch(profilePreferencesProvider);
    const defaults = PlayerSettings();
    final scale = profile.getDouble(_subtitleScale);
    return PlayerSettings(
      quality: StreamQuality.values.asNameMap()[prefs.getString(_quality)] ??
          defaults.quality,
      hardwareDecoding:
          prefs.getBool(_hardwareDecoding) ?? defaults.hardwareDecoding,
      subtitleScale: scale != null && subtitleScaleOptions.contains(scale)
          ? scale
          : defaults.subtitleScale,
      autoSkipIntro: profile.getBool(_autoSkipIntro) ?? defaults.autoSkipIntro,
      autoplayNext: profile.getBool(_autoplayNext) ?? defaults.autoplayNext,
    );
  }

  Future<void> update(PlayerSettings next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    final profile = ref.read(profilePreferencesProvider);
    await Future.wait([
      prefs.setString(_quality, next.quality.name),
      prefs.setBool(_hardwareDecoding, next.hardwareDecoding),
      profile.setDouble(_subtitleScale, next.subtitleScale),
      profile.setBool(_autoSkipIntro, next.autoSkipIntro),
      profile.setBool(_autoplayNext, next.autoplayNext),
    ]);
  }
}

final playerSettingsProvider =
    NotifierProvider<PlayerSettingsController, PlayerSettings>(
        PlayerSettingsController.new);
