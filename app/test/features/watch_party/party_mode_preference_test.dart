import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/syncplay/party_mode.dart';
import 'package:wonderflix/features/watch_party/party_mode_preference.dart';

void main() {
  Future<ProviderContainer> container(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  }

  test('di default pubblico; la scelta si ricorda', () async {
    final first = await container({});
    expect(first.read(partyModePreferenceProvider), PartyMode.public);
    await first.read(partyModePreferenceProvider.notifier).set(PartyMode.friends);
    expect(first.read(partyModePreferenceProvider), PartyMode.friends);

    final prefs = first.read(sharedPreferencesProvider);
    expect(prefs.getString(PartyModePreference.key), 'Friends');
  });

  test('legge il valore salvato; uno sconosciuto vale pubblico', () async {
    expect((await container({PartyModePreference.key: 'Private'}))
        .read(partyModePreferenceProvider), PartyMode.private);
    expect((await container({PartyModePreference.key: 'boh'}))
        .read(partyModePreferenceProvider), PartyMode.public);
  });
}
