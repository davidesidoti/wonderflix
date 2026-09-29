import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../settings/locale_controller.dart';
import 'discord_activity.dart';

/// Testi dell'attività nella lingua dell'app (quella scelta, o quella di
/// Windows risolta come fa `MaterialApp`).
final discordLabelsProvider = Provider<DiscordLabels>((ref) {
  final locale = ref.watch(localeProvider) ??
      basicLocaleListResolution(PlatformDispatcher.instance.locales,
          AppLocalizations.supportedLocales);
  final l = lookupAppLocalizations(locale);
  return DiscordLabels(paused: l.discordPaused, button: l.discordJoinButton);
});
