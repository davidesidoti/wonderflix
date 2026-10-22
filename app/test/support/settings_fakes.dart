import 'dart:async';

import 'package:wonderflix/core/jellyfin/system_api.dart';
import 'package:wonderflix/core/jellyfin/user_config_api.dart';

/// `UserConfigApi` in memoria.
class FakeUserConfigApi implements UserConfigApi {
  Map<String, dynamic> config = {
    'AudioLanguagePreference': 'ita',
    'SubtitleLanguagePreference': '',
    'SubtitleMode': 'Default',
    'HidePlayedInLatest': true,
  };

  /// Se valorizzato, [saveConfiguration] lancia questo errore.
  Object? saveError;

  /// Quanti dei prossimi salvataggi falliscono (dopo [saveGate]).
  int failSaves = 0;

  /// Se valorizzato, [saveConfiguration] aspetta che si completi.
  Completer<void>? saveGate;
  int configurationCalls = 0;
  final saved = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> configuration() async {
    configurationCalls++;
    return Map<String, dynamic>.of(config);
  }

  @override
  Future<void> saveConfiguration(
      String userId, Map<String, dynamic> configuration) async {
    await saveGate?.future;
    final failure = saveError;
    if (failure != null) throw failure;
    if (failSaves > 0) {
      failSaves--;
      throw StateError('salvataggio simulato non riuscito');
    }
    saved.add((userId, configuration));
    config = Map<String, dynamic>.of(configuration);
  }
}

/// `SystemApi` in memoria; con [version] `null` il server non risponde.
class FakeSystemApi implements SystemApi {
  String? version = '10.11.9';

  @override
  Future<String> serverVersion() async {
    final current = version;
    if (current == null) throw StateError('server non raggiungibile');
    return current;
  }
}
