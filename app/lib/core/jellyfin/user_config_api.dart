import 'api_exception.dart';
import 'jellyfin_http.dart';

/// Lingue proposte nelle impostazioni, con il nome nella lingua stessa.
/// Codici ISO 639-2/B, come li salva jellyfin-web (`ThreeLetterISOLanguageName`
/// delle culture del server): per francese, tedesco e cinese sono `fre`,
/// `ger` e `chi`, non `fra`, `deu` e `zho`.
const playbackLanguages = <String, String>{
  'ita': 'Italiano',
  'eng': 'English',
  'jpn': '日本語',
  'fre': 'Français',
  'ger': 'Deutsch',
  'spa': 'Español',
  'por': 'Português',
  'kor': '한국어',
  'chi': '中文',
};

/// Modi dei sottotitoli di Jellyfin (`SubtitlePlaybackMode`).
const subtitleModes = ['Default', 'Always', 'OnlyForced', 'None', 'Smart'];

/// Configurazione dell'utente salvata sul server (vale per tutti i client).
class UserConfigApi {
  UserConfigApi(this._http);

  final JellyfinHttp _http;

  /// Configurazione completa, compresi i campi che l'app non usa. Se la
  /// risposta non la contiene è un errore: salvare una configurazione vuota
  /// cancellerebbe quella sul server.
  Future<Map<String, dynamic>> configuration() async {
    final me = asJsonMap(await _http.get('/Users/Me'));
    final config = me['Configuration'];
    if (config is! Map<String, dynamic>) {
      throw const ServerErrorException(null);
    }
    return Map<String, dynamic>.of(config);
  }

  /// Il server sostituisce tutta la configurazione: [configuration] deve
  /// essere quella completa letta da [configuration()], modificata.
  Future<void> saveConfiguration(
      String userId, Map<String, dynamic> configuration) async {
    await _http.post('/Users/Configuration',
        query: {'userId': userId}, body: configuration);
  }
}

/// Lingue di audio e sottotitoli preferite. Stringa vuota = qualsiasi.
class LanguagePreferences {
  const LanguagePreferences({
    this.audioLanguage = '',
    this.subtitleLanguage = '',
    this.subtitleMode = 'Default',
  });

  factory LanguagePreferences.fromConfiguration(Map<String, dynamic> config) =>
      LanguagePreferences(
        audioLanguage: config['AudioLanguagePreference'] as String? ?? '',
        subtitleLanguage: config['SubtitleLanguagePreference'] as String? ?? '',
        subtitleMode: config['SubtitleMode'] as String? ?? 'Default',
      );

  final String audioLanguage;
  final String subtitleLanguage;

  /// Uno di [subtitleModes].
  final String subtitleMode;

  LanguagePreferences copyWith({
    String? audioLanguage,
    String? subtitleLanguage,
    String? subtitleMode,
  }) =>
      LanguagePreferences(
        audioLanguage: audioLanguage ?? this.audioLanguage,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        subtitleMode: subtitleMode ?? this.subtitleMode,
      );

  /// [configuration] con queste preferenze; gli altri campi restano uguali.
  Map<String, dynamic> applyTo(Map<String, dynamic> configuration) => {
        ...configuration,
        'AudioLanguagePreference': audioLanguage,
        'SubtitleLanguagePreference': subtitleLanguage,
        'SubtitleMode': subtitleMode,
      };
}
