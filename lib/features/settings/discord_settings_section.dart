import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../discord/discord_settings.dart';

/// Rich Presence di Discord: cosa mostrare agli amici.
class DiscordSettingsSection extends ConsumerWidget {
  const DiscordSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(discordSettingsProvider);
    void save(DiscordSettings next) =>
        unawaited(ref.read(discordSettingsProvider.notifier).update(next));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('discord-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsDiscordEnabled),
            value: settings.enabled,
            onChanged: (value) => save(settings.copyWith(enabled: value)),
          ),
          SwitchListTile(
            key: const Key('discord-show-title'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsDiscordShowTitle),
            value: settings.showTitle,
            onChanged: settings.enabled
                ? (value) => save(settings.copyWith(showTitle: value))
                : null,
          ),
          SwitchListTile(
            key: const Key('discord-show-poster'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsDiscordShowPoster),
            subtitle: Text(l.settingsDiscordPosterHint),
            value: settings.showPoster,
            onChanged: settings.enabled && settings.showTitle
                ? (value) => save(settings.copyWith(showPoster: value))
                : null,
          ),
        ],
      ),
    );
  }
}
