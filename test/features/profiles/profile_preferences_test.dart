import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/core/syncplay/party_mode.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/profiles/profile_preferences.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';
import 'package:wonderflix/features/watch_party/party_mode_preference.dart';

import '../../support/profile_fakes.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // Le preferenze di oggi, del PC: valgono come partenza per i profili.
      'locale': 'it',
      'player.subtitleScale': 1.0,
      'player.quality': 'mbps8',
      'discord.enabled': false,
    });
    prefs = await SharedPreferences.getInstance();
  });

  group('ProfilePreferences', () {
    test('senza profilo: le chiavi del PC', () async {
      final own = ProfilePreferences(prefs, null);
      expect(own.getString('locale'), 'it');
      await own.setString('locale', 'en');
      expect(prefs.getString('locale'), 'en');
      await own.clearString('locale');
      expect(prefs.containsKey('locale'), isFalse);
    });

    test('con un profilo: la sua chiave, altrimenti quella del PC', () async {
      final mario = ProfilePreferences(prefs, 'AB-CD');
      expect(mario.getString('locale'), 'it');
      await mario.setString('locale', 'en');
      expect(prefs.getString('profile.abcd.locale'), 'en');
      expect(prefs.getString('locale'), 'it');
      expect(mario.getString('locale'), 'en');
      expect(mario.getDouble('player.subtitleScale'), 1.0);
      await mario.setBool('discord.enabled', true);
      expect(mario.getBool('discord.enabled'), isTrue);
      expect(prefs.getBool('discord.enabled'), isFalse);
    });

    test('clearString in un profilo: vuoto, non la chiave del PC', () async {
      final mario = ProfilePreferences(prefs, 'u1');
      await mario.clearString('locale');
      expect(mario.getString('locale'), '');
    });

    test('forget cancella solo le chiavi di quel profilo', () async {
      await ProfilePreferences(prefs, 'u1').setString('locale', 'en');
      await ProfilePreferences(prefs, 'u2').setString('locale', 'it');

      await ProfilePreferences.forget(prefs, 'U-1');

      expect(prefs.containsKey('profile.u1.locale'), isFalse);
      expect(prefs.getString('profile.u2.locale'), 'it');
      expect(prefs.getString('locale'), 'it');
    });
  });

  group('i controller seguono il profilo', () {
    late FixedProfiles profiles;

    ProviderContainer container(ProfilesState initial) {
      profiles = FixedProfiles(initial);
      return ProviderContainer.test(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          profilesProvider.overrideWith(() => profiles),
        ],
        retry: (_, _) => null,
      );
    }

    final book = const ProfileBook()
        .upsert(testProfile(userId: 'u1'))
        .upsert(testProfile(userId: 'u2'))
        .withLast('u2');

    test('lingua: del profilo aperto, poi dell\'ultimo usato', () async {
      final c = container(ProfilesState(book: book, activeUserId: 'u1'));
      expect(c.read(localeProvider), const Locale('it'));
      await c.read(localeProvider.notifier).set(const Locale('en'));
      expect(c.read(localeProvider), const Locale('en'));

      // Nessun profilo aperto: vale l'ultimo usato (u2), che parte dal PC.
      profiles.set(ProfilesState(book: book));
      expect(c.read(localeProvider), const Locale('it'));

      // "Lingua di Windows" in un profilo non torna a quella del PC.
      profiles.set(ProfilesState(book: book, activeUserId: 'u1'));
      await c.read(localeProvider.notifier).set(null);
      expect(c.read(localeProvider), isNull);
    });

    test('player: sottotitoli del profilo, qualità del PC', () async {
      final c = container(ProfilesState(book: book, activeUserId: 'u1'));
      final controller = c.read(playerSettingsProvider.notifier);
      await controller.update(c.read(playerSettingsProvider)
          .copyWith(subtitleScale: 0.6, quality: StreamQuality.mbps4));

      expect(prefs.getDouble('profile.u1.player.subtitleScale'), 0.6);
      expect(prefs.getString('player.quality'), 'mbps4');
      expect(prefs.containsKey('profile.u1.player.quality'), isFalse);

      profiles.set(ProfilesState(book: book, activeUserId: 'u2'));
      final other = c.read(playerSettingsProvider);
      expect(other.subtitleScale, 1.0);
      expect(other.quality, StreamQuality.mbps4);
    });

    test('Discord e modalità del party: del profilo', () async {
      final c = container(ProfilesState(book: book, activeUserId: 'u1'));
      await c.read(discordSettingsProvider.notifier).update(
          c.read(discordSettingsProvider).copyWith(enabled: true));
      await c.read(partyModePreferenceProvider.notifier).set(PartyMode.private);

      profiles.set(ProfilesState(book: book, activeUserId: 'u2'));
      expect(c.read(discordSettingsProvider).enabled, isFalse);
      expect(c.read(partyModePreferenceProvider), PartyMode.public);

      profiles.set(ProfilesState(book: book, activeUserId: 'u1'));
      expect(c.read(discordSettingsProvider).enabled, isTrue);
      expect(c.read(partyModePreferenceProvider), PartyMode.private);
    });
  });
}
