import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
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

  test('configuration senza "Configuration": errore, non una mappa vuota',
      () async {
    // Salvare una configurazione vuota cancellerebbe quella sul server.
    adapter.handler =
        (_) => const FakeResponse(200, {'Id': 'u1', 'Name': 'Mario'});
    await expectLater(
        api.configuration(), throwsA(isA<ServerErrorException>()));
  });

  test('lingue con i codici ISO 639-2/B usati da Jellyfin', () {
    expect(playbackLanguages.keys, containsAll(['fre', 'ger', 'chi']));
    expect(playbackLanguages.keys, isNot(contains('fra')));
    expect(playbackLanguages.keys, isNot(contains('deu')));
    expect(playbackLanguages.keys, isNot(contains('zho')));
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
