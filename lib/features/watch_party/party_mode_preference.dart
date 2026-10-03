import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/syncplay/party_mode.dart';

/// Ultima modalità scelta su "Guarda insieme", evidenziata nel menu (spec F
/// §9.1). Di default pubblico.
class PartyModePreference extends Notifier<PartyMode> {
  static const key = 'party.lastMode';

  @override
  PartyMode build() =>
      PartyMode.fromWire(ref.watch(sharedPreferencesProvider).getString(key)) ??
      PartyMode.public;

  Future<void> set(PartyMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(key, mode.wire);
  }
}

final partyModePreferenceProvider =
    NotifierProvider<PartyModePreference, PartyMode>(PartyModePreference.new);
