import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/logging/app_log.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/settings/diagnostics.dart';

import '../../support/settings_fakes.dart';
import '../../support/test_data.dart';

void main() {
  test('buildDiagnostics: testo completo', () {
    expect(
        buildDiagnostics(
          appVersion: '0.1.0',
          windowsVersion: '"Windows 11 Pro" 10.0 (Build 26200)',
          serverVersion: '10.11.9',
          player: const PlayerSettings(),
          discord: const DiscordSettings(showPoster: false),
          recentErrors: ['riga 1', 'riga 2'],
        ),
        'WonderFlix 0.1.0\n'
        'Windows: "Windows 11 Pro" 10.0 (Build 26200)\n'
        'Jellyfin: 10.11.9\n'
        'Player: quality=original, hardwareDecoding=true, subtitleScale=1.0, '
        'autoSkipIntro=false, autoplayNext=true\n'
        'Discord: enabled=true, showTitle=true, showPoster=false\n'
        '\n'
        'Ultimi errori (2):\n'
        'riga 1\n'
        'riga 2\n');
  });

  test('buildDiagnostics: server irraggiungibile, nessun errore', () {
    final text = buildDiagnostics(
      appVersion: '0.1.0',
      windowsVersion: 'w',
      serverVersion: null,
      player: const PlayerSettings(),
      discord: const DiscordSettings(),
      recentErrors: const [],
    );
    expect(text, contains('Jellyfin: non raggiungibile\n'));
    expect(text, endsWith('Ultimi errori (0):\nnessuno\n'));
  });

  Future<ProviderContainer> container(FakeSystemApi system) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final log = AppLog()..add(LogRecord(Level.SEVERE, 'boom', 'player'));
    return ProviderContainer.test(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      systemApiProvider.overrideWithValue(system),
      appLogProvider.overrideWithValue(log),
    ]);
  }

  test('collectDiagnostics: versioni, impostazioni ed errori dell\'app',
      () async {
    final c = await container(FakeSystemApi());
    final text = await c.read(collectDiagnosticsProvider)();
    expect(text, startsWith('WonderFlix 0.0.1\nWindows: '));
    expect(text, contains('Jellyfin: 10.11.9\n'));
    expect(text, contains('Player: quality=original'));
    expect(text, contains('Discord: enabled=true'));
    expect(text, contains('[player] boom'));
  });

  test('collectDiagnostics: server offline', () async {
    final c = await container(FakeSystemApi()..version = null);
    final text = await c.read(collectDiagnosticsProvider)();
    expect(text, contains('Jellyfin: non raggiungibile\n'));
  });
}
