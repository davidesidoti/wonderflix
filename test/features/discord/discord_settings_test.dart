import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/discord/discord_providers.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';

void main() {
  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  }

  test('impostazioni: tutte attive di default, salvate e rilette', () async {
    final first = await container();
    const defaults = DiscordSettings();
    expect(first.read(discordSettingsProvider).enabled, isTrue);
    expect(first.read(discordSettingsProvider).showTitle, isTrue);
    expect(first.read(discordSettingsProvider).showPoster, isTrue);

    await first.read(discordSettingsProvider.notifier).update(defaults.copyWith(
        enabled: false, showTitle: false, showPoster: false));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('discord.enabled'), isFalse);

    final again = ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final settings = again.read(discordSettingsProvider);
    expect(settings.enabled, isFalse);
    expect(settings.showTitle, isFalse);
    expect(settings.showPoster, isFalse);
  });

  test('testi per Discord nella lingua scelta', () async {
    final c = await container();
    await c.read(localeProvider.notifier).set(const Locale('en'));
    expect(c.read(discordLabelsProvider).paused, 'Paused');
    await c.read(localeProvider.notifier).set(const Locale('it'));
    expect(c.read(discordLabelsProvider).paused, 'In pausa');
    expect(c.read(discordLabelsProvider).button, "Chiedi l'accesso");
  });
}
