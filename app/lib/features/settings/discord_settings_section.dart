import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../admin/admin_kit.dart';
import '../discord/discord_settings.dart';
import 'settings_kit.dart';

/// Rich Presence di Discord: cosa mostrare agli amici.
class DiscordSettingsSection extends ConsumerWidget {
  const DiscordSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(discordSettingsProvider);
    void save(DiscordSettings next) =>
        unawaited(ref.read(discordSettingsProvider.notifier).update(next));

    // Titolo e locandina dipendono dalla voce sopra: rientrate.
    return AdminList(
      children: [
        SettingsSwitchRow(
          key: const Key('discord-enabled'),
          label: l.settingsDiscordEnabled,
          value: settings.enabled,
          onChanged: (value) => save(settings.copyWith(enabled: value)),
        ),
        SettingsSwitchRow(
          key: const Key('discord-show-title'),
          label: l.settingsDiscordShowTitle,
          indent: 20,
          value: settings.showTitle,
          onChanged: settings.enabled
              ? (value) => save(settings.copyWith(showTitle: value))
              : null,
        ),
        SettingsSwitchRow(
          key: const Key('discord-show-poster'),
          label: l.settingsDiscordShowPoster,
          hint: l.settingsDiscordPosterHint,
          indent: 20,
          value: settings.showPoster,
          onChanged: settings.enabled && settings.showTitle
              ? (value) => save(settings.copyWith(showPoster: value))
              : null,
        ),
      ],
    );
  }
}
