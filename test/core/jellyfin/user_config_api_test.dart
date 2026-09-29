import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/user_config_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late UserConfigApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = UserConfigApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('configuration legge tutti i campi', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Id': 'u1',
          'Name': 'Mario',
          'Configuration': {
            'AudioLanguagePreference': 'ita',
            'SubtitleMode': 'Smart',
            'HidePlayedInLatest': true,
          },
        });
    final config = await api.configuration();
    expect(adapter.requests.last.path, '/Users/Me');
    expect(config, {
      'AudioLanguagePreference': 'ita',
      'SubtitleMode': 'Smart',
      'HidePlayedInLatest': true,
    });
  });

  test('saveConfiguration invia la configurazione completa', () async {
    await api.saveConfiguration('u1', {'SubtitleMode': 'None', 'X': 1});
    final request = adapter.requests.last;
    expect(request.method, 'POST');
    expect(request.path, '/Users/Configuration');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(request.data, {'SubtitleMode': 'None', 'X': 1});
  });

  test('LanguagePreferences: lettura e scrittura senza perdere altri campi',
      () {
    final prefs = LanguagePreferences.fromConfiguration(const {
      'AudioLanguagePreference': 'jpn',
      'SubtitleLanguagePreference': null,
      'HidePlayedInLatest': true,
    });
    expect(prefs.audioLanguage, 'jpn');
    expect(prefs.subtitleLanguage, '');
    expect(prefs.subtitleMode, 'Default');

    final updated = prefs
        .copyWith(subtitleLanguage: 'ita', subtitleMode: 'Always')
        .applyTo(const {'HidePlayedInLatest': true, 'SubtitleMode': 'Default'});
    expect(updated, {
      'HidePlayedInLatest': true,
      'SubtitleMode': 'Always',
      'AudioLanguagePreference': 'jpn',
      'SubtitleLanguagePreference': 'ita',
    });
  });
}
