import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/discord/discord_ipc.dart';
import '../../core/discord/windows_discord_pipe.dart';
import '../../core/media_session/media_session.dart';
import '../../l10n/gen/app_localizations.dart';
import '../settings/locale_controller.dart';
import 'discord_activity.dart';
import 'discord_presence.dart';
import 'discord_settings.dart';

/// Testi dell'attività nella lingua dell'app (quella scelta, o quella di
/// Windows risolta come fa `MaterialApp`).
final discordLabelsProvider = Provider<DiscordLabels>((ref) {
  final locale = ref.watch(localeProvider) ??
      basicLocaleListResolution(PlatformDispatcher.instance.locales,
          AppLocalizations.supportedLocales);
  final l = lookupAppLocalizations(locale);
  return DiscordLabels(paused: l.discordPaused, button: l.discordAccessButton);
});

/// Crea la pipe verso Discord; nei test si usa una pipe finta.
final discordPipeFactoryProvider =
    Provider<DiscordPipe Function()>((ref) => WindowsDiscordPipe.new);

/// Attività su Discord. Di default non fa nulla; `main` la sostituisce con
/// [createDiscordPresence].
final discordSessionProvider = Provider<MediaSession>((ref) {
  final session = NoopMediaSession();
  ref.onDispose(() => unawaited(session.dispose()));
  return session;
});

/// Snowflake di Discord: 17–20 cifre, non il valore d'esempio tutto zeri.
final _applicationId = RegExp(r'^[1-9]\d{16,19}$');

/// La Rich Presence vera, se `discordAppId` è un Application ID valido.
MediaSession createDiscordPresence(Ref ref) {
  final config = ref.watch(appConfigProvider);
  final appId = config.discordAppId;
  if (!_applicationId.hasMatch(appId)) return NoopMediaSession();
  final createPipe = ref.watch(discordPipeFactoryProvider);
  final presence = DiscordPresence(
    createClient: () => DiscordIpcClient(createPipe(), clientId: appId),
    settings: () => ref.read(discordSettingsProvider),
    labels: () => ref.read(discordLabelsProvider),
    buttonUrl: config.accessRequestUrl,
  );
  ref.listen(discordSettingsProvider, (_, _) => presence.refresh());
  ref.listen(discordLabelsProvider, (_, _) => presence.refresh());
  ref.onDispose(() => unawaited(presence.dispose()));
  return presence;
}
