import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/json_fields.dart';
import '../auth/profiles_state.dart';

/// Prefisso delle preferenze di un profilo (spec K §9.6).
String profilePreferencesPrefix(String userId) =>
    'profile.${jellyfinIdKey(userId)}.';

/// Le preferenze del profilo (spec K §9.6): lingua, modalità del party,
/// Discord, dimensione dei sottotitoli, salto dell'intro, episodio
/// successivo. Si legge la chiave del profilo e, se manca, quella del PC (il
/// valore di partenza); si scrive sempre nel profilo. Senza profilo valgono
/// le chiavi del PC, come prima della 0.11.0.
class ProfilePreferences {
  const ProfilePreferences(this._prefs, this.userId);

  final SharedPreferences _prefs;

  /// Il profilo; `null`: le preferenze del PC.
  final String? userId;

  String _key(String key) {
    final id = userId;
    return id == null ? key : '${profilePreferencesPrefix(id)}$key';
  }

  String? getString(String key) =>
      (userId == null ? null : _prefs.getString(_key(key))) ??
      _prefs.getString(key);

  bool? getBool(String key) =>
      (userId == null ? null : _prefs.getBool(_key(key))) ??
      _prefs.getBool(key);

  double? getDouble(String key) =>
      (userId == null ? null : _prefs.getDouble(_key(key))) ??
      _prefs.getDouble(key);

  Future<bool> setString(String key, String value) =>
      _prefs.setString(_key(key), value);

  Future<bool> setBool(String key, bool value) =>
      _prefs.setBool(_key(key), value);

  Future<bool> setDouble(String key, double value) =>
      _prefs.setDouble(_key(key), value);

  /// Nessun valore. In un profilo resta una stringa vuota: senza valore
  /// varrebbe quella del PC.
  Future<bool> clearString(String key) =>
      userId == null ? _prefs.remove(key) : _prefs.setString(_key(key), '');

  /// Cancella le preferenze di [userId] (profilo tolto dal PC, spec K §9.6).
  static Future<void> removeProfile(
      SharedPreferences prefs, String userId) async {
    final prefix = profilePreferencesPrefix(userId);
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

/// Le preferenze del profilo aperto, o dell'ultimo usato (spec K §9.6): chi le
/// guarda rilegge i valori a ogni cambio di profilo.
final profilePreferencesProvider = Provider<ProfilePreferences>((ref) =>
    ProfilePreferences(ref.watch(sharedPreferencesProvider),
        ref.watch(profilesProvider.select((p) => p.preferenceUserId))));
