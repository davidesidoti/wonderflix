import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/syncplay/party_mode.dart';
import '../profiles/profile_preferences.dart';

/// Ultima modalità scelta su "Guarda insieme", evidenziata nel menu (spec F
/// §9.1). Di default pubblico. Preferenza del profilo (spec K §9.6).
class PartyModePreference extends Notifier<PartyMode> {
  static const key = 'party.lastMode';

  @override
  PartyMode build() =>
      PartyMode.fromWire(
          ref.watch(profilePreferencesProvider).getString(key)) ??
      PartyMode.public;

  Future<void> set(PartyMode mode) async {
    state = mode;
    await ref.read(profilePreferencesProvider).setString(key, mode.wire);
  }
}

final partyModePreferenceProvider =
    NotifierProvider<PartyModePreference, PartyMode>(PartyModePreference.new);
