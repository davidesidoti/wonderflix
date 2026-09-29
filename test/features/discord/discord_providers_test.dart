import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/config/app_config.dart';
import 'package:wonderflix/core/media_session/media_session.dart';
import 'package:wonderflix/features/discord/discord_providers.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';
import 'package:wonderflix/features/player/player_providers.dart';

import '../../support/discord_fakes.dart';
import '../../support/test_data.dart';

void main() {
  AppConfig config(String discordAppId,
          {Uri? supportUrl, Uri? accessRequestUrl}) =>
      AppConfig(
        serverUrl: testServerUrl,
        githubRepo: 'owner/repo',
        discordAppId: discordAppId,
        supportUrl: supportUrl,
        accessRequestUrl: accessRequestUrl,
      );

  /// L'attività inviata a Discord con [config] mentre si guarda un titolo.
  Future<Map<String, Object?>> sentActivity(AppConfig config) async {
    SharedPreferences.setMockInitialValues({'locale': 'it'});
    final prefs = await SharedPreferences.getInstance();
    final pipe = FakeDiscordPipe();
    late Map<String, Object?> activity;
    fakeAsync((async) {
      final container = ProviderContainer(overrides: [
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
        discordPipeFactoryProvider.overrideWithValue(() => pipe),
        discordSessionProvider.overrideWith(createDiscordPresence),
      ]);
      unawaited(container
          .read(mediaSessionProvider)
          .setMetadata(title: 'Heat', subtitle: '1995'));
      async.flushMicrotasks();
      activity = pipe.activities.single!;
      container.dispose();
      async.flushMicrotasks();
    });
    return activity;
  }

  test('il pulsante non usa supportUrl: senza accessRequestUrl nessun '
      'pulsante', () async {
    final activity = await sentActivity(config('123456789012345678',
        supportUrl: Uri.parse('https://discord.gg/abc')));
    expect(activity.containsKey('buttons'), isFalse);
  });

  test('il pulsante apre accessRequestUrl', () async {
    final activity = await sentActivity(config('123456789012345678',
        supportUrl: Uri.parse('https://discord.gg/abc'),
        accessRequestUrl:
            Uri.parse('https://discord.com/users/390840489290760192')));
    expect(activity['buttons'], [
      {
        'label': "Chiedi l'accesso",
        'url': 'https://discord.com/users/390840489290760192',
      },
    ]);
  });

  test('Application ID valido: il player aggiorna Discord, che segue le '
      'impostazioni', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final pipe = FakeDiscordPipe();
    fakeAsync((async) {
      final container = ProviderContainer(overrides: [
        appConfigProvider.overrideWithValue(config('123456789012345678')),
        sharedPreferencesProvider.overrideWithValue(prefs),
        discordPipeFactoryProvider.overrideWithValue(() => pipe),
        discordSessionProvider.overrideWith(createDiscordPresence),
      ]);
      final session = container.read(mediaSessionProvider);
      unawaited(session.setMetadata(title: 'Heat', subtitle: '1995'));
      async.flushMicrotasks();
      expect(pipe.activities.single!['details'], 'Heat');

      unawaited(container
          .read(discordSettingsProvider.notifier)
          .update(const DiscordSettings(enabled: false)));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities.last, isNull);

      container.dispose();
      async.flushMicrotasks();
    });
  });

  test('Application ID d\'esempio o vuoto: nessuna connessione', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    for (final id in ['000000000000000000', '', '1']) {
      final pipe = FakeDiscordPipe();
      final container = ProviderContainer.test(overrides: [
        appConfigProvider.overrideWithValue(config(id)),
        sharedPreferencesProvider.overrideWithValue(prefs),
        discordPipeFactoryProvider.overrideWithValue(() => pipe),
        discordSessionProvider.overrideWith(createDiscordPresence),
      ]);
      expect(container.read(discordSessionProvider), isA<NoopMediaSession>());
    }
  });
}
