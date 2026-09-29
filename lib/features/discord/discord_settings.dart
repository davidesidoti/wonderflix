import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Preferenze della Rich Presence di Discord, salvate su questo PC.
class DiscordSettings {
  const DiscordSettings({
    this.enabled = true,
    this.showTitle = true,
    this.showPoster = true,
  });

  /// Mostra l'attività su Discord.
  final bool enabled;

  /// Mostra titolo ed episodio (spento: solo "WonderFlix" e i tempi).
  final bool showTitle;

  /// Usa la locandina dal server invece del logo. Rende visibile l'indirizzo
  /// del server agli amici su Discord.
  final bool showPoster;

  DiscordSettings copyWith({bool? enabled, bool? showTitle, bool? showPoster}) =>
      DiscordSettings(
        enabled: enabled ?? this.enabled,
        showTitle: showTitle ?? this.showTitle,
        showPoster: showPoster ?? this.showPoster,
      );
}

class DiscordSettingsController extends Notifier<DiscordSettings> {
  static const _enabled = 'discord.enabled';
  static const _showTitle = 'discord.showTitle';
  static const _showPoster = 'discord.showPoster';

  @override
  DiscordSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    const defaults = DiscordSettings();
    return DiscordSettings(
      enabled: prefs.getBool(_enabled) ?? defaults.enabled,
      showTitle: prefs.getBool(_showTitle) ?? defaults.showTitle,
      showPoster: prefs.getBool(_showPoster) ?? defaults.showPoster,
    );
  }

  Future<void> update(DiscordSettings next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setBool(_enabled, next.enabled),
      prefs.setBool(_showTitle, next.showTitle),
      prefs.setBool(_showPoster, next.showPoster),
    ]);
  }
}

final discordSettingsProvider =
    NotifierProvider<DiscordSettingsController, DiscordSettings>(
        DiscordSettingsController.new);
