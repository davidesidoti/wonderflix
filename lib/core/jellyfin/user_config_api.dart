import 'jellyfin_http.dart';

/// Lingue proposte nelle impostazioni (codici ISO 639-2 usati da Jellyfin),
/// con il nome nella lingua stessa.
const playbackLanguages = <String, String>{
  'ita': 'Italiano',
  'eng': 'English',
  'jpn': '日本語',
  'fra': 'Français',
  'deu': 'Deutsch',
  'spa': 'Español',
  'por': 'Português',
  'kor': '한국어',
  'zho': '中文',
};

/// Modi dei sottotitoli di Jellyfin (`SubtitlePlaybackMode`).
const subtitleModes = ['Default', 'Always', 'OnlyForced', 'None', 'Smart'];

/// Configurazione dell'utente salvata sul server (vale per tutti i client).
class UserConfigApi {
  UserConfigApi(this._http);

  final JellyfinHttp _http;

  /// Configurazione completa, compresi i campi che l'app non usa.
  Future<Map<String, dynamic>> configuration() async {
    final me = asJsonMap(await _http.get('/Users/Me'));
    final config = me['Configuration'];
    return config is Map<String, dynamic>
        ? Map<String, dynamic>.of(config)
        : <String, dynamic>{};
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
