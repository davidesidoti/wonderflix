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
  final saved = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> configuration() async =>
      Map<String, dynamic>.of(config);

  @override
  Future<void> saveConfiguration(
      String userId, Map<String, dynamic> configuration) async {
    final failure = saveError;
    if (failure != null) throw failure;
    saved.add((userId, configuration));
    config = Map<String, dynamic>.of(configuration);
  }
}
