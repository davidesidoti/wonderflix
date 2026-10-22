import 'dart:io';

import '../storage/profile_store.dart';
import '../storage/session_store.dart';

/// Profilo di sviluppo (variabile d'ambiente `WONDERFLIX_PROFILE`): una
/// seconda istanza con dati e `DeviceId` propri, per provare il watch party
/// sullo stesso PC (spec B §7.2). `null` = istanza normale.
String? devProfile([Map<String, String>? environment]) {
  final value = (environment ?? Platform.environment)['WONDERFLIX_PROFILE']
      ?.trim()
      .toLowerCase();
  if (value == null || !RegExp(r'^[a-z0-9]{1,16}$').hasMatch(value)) {
    return null;
  }
  return value;
}

/// Prefisso delle `SharedPreferences` (quello predefinito è `flutter.`).
String prefsPrefixFor(String? profile) =>
    profile == null ? 'flutter.' : 'flutter.$profile.';

/// Chiave della sessione di prima della 0.11.0 (migrazione nei profili).
String sessionKeyFor(String? profile) => profile == null
    ? SecureSessionStore.key
    : '${SecureSessionStore.key}.$profile';

/// Chiave dei profili (spec K §9.1); l'istanza di sviluppo ha la sua.
String profilesKeyFor(String? profile) => profile == null
    ? SecureProfileStore.defaultKey
    : '${SecureProfileStore.defaultKey}.$profile';

/// Cartella dei log dentro `%LocalAppData%\WonderFlix`.
String logsFolderFor(String? profile) =>
    profile == null ? 'logs' : 'logs-$profile';
