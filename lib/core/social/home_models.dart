import '../jellyfin/json_fields.dart';

/// Perché il plugin non ha dato le uscite (spec M §7.4). I codici arrivano
/// in PascalCase.
enum UpcomingError {
  notConfigured('NotConfigured'),
  unauthorized('Unauthorized'),
  unreachable('Unreachable');

  const UpcomingError(this.wire);

  final String wire;

  /// `null` senza errore (Jellyfin può non scrivere il campo); un codice
  /// sconosciuto vale come irraggiungibile.
  static UpcomingError? parse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    for (final error in values) {
      if (error.wire == raw) return error;
    }
    return unreachable;
  }
}

/// Le uscite di Sonarr o Radarr come le dà il plugin (spec M §7.3): con un
/// errore l'elenco è vuoto.
class UpcomingPage<T> {
  const UpcomingPage({this.items = const [], this.error});

  factory UpcomingPage.fromJson(Map<String, dynamic> json,
          T? Function(Map<String, dynamic> json) parse) =>
      UpcomingPage(
        items: json['Items'] is List ? jsonList(json['Items'], parse) : const [],
        error: UpcomingError.parse(json['Error']),
      );

  final List<T> items;
  final UpcomingError? error;
}

/// Un episodio in arrivo, o un blocco di episodi usciti insieme (spec M
/// §7.3): [lastEpisodeNumber] c'è solo per un blocco.
class UpcomingEpisode {
  const UpcomingEpisode({
    required this.seriesName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.airDate,
    this.lastEpisodeNumber,
    this.episodeTitle,
    this.tvdbId,
    this.tmdbId,
    this.posterUrl,
    this.backdropUrl,
    this.jellyfinSeriesId,
    this.onServer = false,
  });

  /// `null` senza nome della serie, numeri o una data valida: la voce si
  /// scarta.
  static UpcomingEpisode? fromJson(Map<String, dynamic> json) {
    final name = jsonString(json, 'SeriesName');
    final season = jsonInt(json, 'SeasonNumber');
    final episode = jsonInt(json, 'EpisodeNumber');
    final airDate = jsonDate(json, 'AirDateUtc');
    if (name == null || season == null || episode == null || airDate == null) {
      return null;
    }
    return UpcomingEpisode(
      seriesName: name,
      seasonNumber: season,
      episodeNumber: episode,
      airDate: airDate,
      lastEpisodeNumber: jsonInt(json, 'LastEpisodeNumber'),
      episodeTitle: jsonString(json, 'EpisodeTitle'),
      tvdbId: jsonInt(json, 'TvdbId'),
      tmdbId: jsonInt(json, 'TmdbId'),
      posterUrl: _webAddress(json, 'PosterUrl'),
      backdropUrl: _webAddress(json, 'BackdropUrl'),
      jellyfinSeriesId: jsonString(json, 'JellyfinSeriesId'),
      onServer: json['OnServer'] == true,
    );
  }

  final String seriesName;
  final int seasonNumber;
  final int episodeNumber;
  final int? lastEpisodeNumber;
  final String? episodeTitle;

  /// Uscita, in UTC.
  final DateTime airDate;
  final int? tvdbId;
  final int? tmdbId;
  final String? posterUrl;
  final String? backdropUrl;

  /// La serie di Jellyfin, solo se l'utente la vede.
  final String? jellyfinSeriesId;

  /// Già sul server (solo nel calendario, spec S §6.4).
  final bool onServer;
}

/// Un film in arrivo (spec M §7.3).
class UpcomingMovie {
  const UpcomingMovie({
    required this.title,
    required this.tmdbId,
    required this.digitalRelease,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.jellyfinItemId,
    this.onServer = false,
  });

  /// `null` senza titolo, id TMDB o data d'uscita: la voce si scarta.
  static UpcomingMovie? fromJson(Map<String, dynamic> json) {
    final title = jsonString(json, 'Title');
    final tmdbId = jsonInt(json, 'TmdbId');
    final release = jsonDate(json, 'DigitalRelease');
    if (title == null || tmdbId == null || release == null) return null;
    return UpcomingMovie(
      title: title,
      tmdbId: tmdbId,
      digitalRelease: release,
      year: jsonInt(json, 'Year'),
      posterUrl: _webAddress(json, 'PosterUrl'),
      backdropUrl: _webAddress(json, 'BackdropUrl'),
      jellyfinItemId: jsonString(json, 'JellyfinItemId'),
      onServer: json['OnServer'] == true,
    );
  }

  final String title;
  final int? year;
  final int tmdbId;

  /// Uscita digitale: una data di calendario, a mezzanotte UTC.
  final DateTime digitalRelease;
  final String? posterUrl;
  final String? backdropUrl;

  /// Il film di Jellyfin, solo se l'utente lo vede (spec S §6.4).
  final String? jellyfinItemId;

  /// Già sul server (solo nel calendario).
  final bool onServer;
}

/// Il calendario delle uscite (spec S §6.4): episodi e film di un periodo,
/// con l'errore di ciascun servizio. Liste mancanti valgono vuote.
class CalendarPage {
  const CalendarPage({
    this.episodes = const [],
    this.movies = const [],
    this.seriesError,
    this.moviesError,
  });

  factory CalendarPage.fromJson(Map<String, dynamic> json) => CalendarPage(
        episodes: json['Episodes'] is List
            ? jsonList(json['Episodes'], UpcomingEpisode.fromJson)
            : const [],
        movies: json['Movies'] is List
            ? jsonList(json['Movies'], UpcomingMovie.fromJson)
            : const [],
        seriesError: UpcomingError.parse(json['SeriesError']),
        moviesError: UpcomingError.parse(json['MoviesError']),
      );

  final List<UpcomingEpisode> episodes;
  final List<UpcomingMovie> movies;
  final UpcomingError? seriesError;
  final UpcomingError? moviesError;
}

/// Solo indirizzi http(s) completi: un'immagine non si chiede a un
/// indirizzo qualunque.
String? _webAddress(Map<String, dynamic> json, String key) {
  final value = jsonString(json, key);
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.scheme == 'https' || uri.scheme == 'http' ? value : null;
}

/// L'esito della prova di un servizio, Sonarr o Radarr (spec M §7.5). I
/// campi null possono mancare: un servizio assente vale non configurato.
class ArrTestResult {
  const ArrTestResult({
    required this.configured,
    required this.ok,
    this.version,
    this.error,
  });

  factory ArrTestResult.fromJson(Map<String, dynamic> json) => ArrTestResult(
        configured: json['Configured'] == true,
        ok: json['Ok'] == true,
        version: jsonString(json, 'Version'),
        error: UpcomingError.parse(json['Error']),
      );

  final bool configured;
  final bool ok;
  final String? version;

  /// `null` se la prova è riuscita.
  final UpcomingError? error;
}

/// `POST Upcoming/Test`: Sonarr e Radarr insieme.
class ArrTestResults {
  const ArrTestResults({required this.sonarr, required this.radarr});

  factory ArrTestResults.fromJson(Map<String, dynamic> json) => ArrTestResults(
        sonarr: ArrTestResult.fromJson(jsonMap(json['Sonarr']) ?? const {}),
        radarr: ArrTestResult.fromJson(jsonMap(json['Radarr']) ?? const {}),
      );

  final ArrTestResult sonarr;
  final ArrTestResult radarr;
}
