import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/device_profile.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  Future<ProviderContainer> container(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  }

  test('valori predefiniti', () async {
    final settings = (await container({})).read(playerSettingsProvider);
    expect(settings.quality, StreamQuality.original);
    expect(settings.hardwareDecoding, isTrue);
    expect(settings.subtitleScale, 1.0);
    expect(settings.autoSkipIntro, isFalse);
    expect(settings.autoplayNext, isTrue);
  });

  test('salva e rilegge', () async {
    final first = await container({});
    await first.read(playerSettingsProvider.notifier).update(const PlayerSettings(
          quality: StreamQuality.mbps8,
          hardwareDecoding: false,
          subtitleScale: 1.25,
          autoSkipIntro: true,
          autoplayNext: false,
        ));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('player.quality'), 'mbps8');

    final again = ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final settings = again.read(playerSettingsProvider);
    expect(settings.quality, StreamQuality.mbps8);
    expect(settings.hardwareDecoding, isFalse);
    expect(settings.subtitleScale, 1.25);
    expect(settings.autoSkipIntro, isTrue);
    expect(settings.autoplayNext, isFalse);
  });

  test('valori salvati non validi: predefiniti', () async {
    final settings = (await container({
      'player.quality': 'boh',
      'player.subtitleScale': 3.0,
    }))
        .read(playerSettingsProvider);
    expect(settings.quality, StreamQuality.original);
    expect(settings.subtitleScale, 1.0);
  });

  test('bitrate delle qualità', () {
    expect(StreamQuality.original.bitrate, originalQualityBitrate);
    expect(StreamQuality.mbps20.bitrate, 20000000);
    expect(StreamQuality.mbps8.bitrate, 8000000);
    expect(StreamQuality.mbps4.bitrate, 4000000);
  });

  test('nomi delle dimensioni dei sottotitoli', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect([for (final scale in subtitleScaleOptions) subtitleScaleLabel(l, scale)],
        ['Piccoli', 'Normali', 'Grandi', 'Molto grandi']);
  });
}
