using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>
/// Un episodio, o un blocco di episodi, di GET Upcoming/Series (spec M §7.3).
/// I campi null possono mancare: Jellyfin può non scrivere i null.
/// </summary>
public sealed record UpcomingEpisodeDto(
    [property: JsonPropertyName("SeriesName")] string SeriesName,
    [property: JsonPropertyName("SeasonNumber")] int SeasonNumber,
    [property: JsonPropertyName("EpisodeNumber")] int EpisodeNumber,
    [property: JsonPropertyName("LastEpisodeNumber")] int? LastEpisodeNumber,
    [property: JsonPropertyName("EpisodeTitle")] string? EpisodeTitle,
    [property: JsonPropertyName("AirDateUtc")] DateTimeOffset AirDateUtc,
    [property: JsonPropertyName("TvdbId")] int? TvdbId,
    [property: JsonPropertyName("TmdbId")] int? TmdbId,
    [property: JsonPropertyName("PosterUrl")] string? PosterUrl,
    [property: JsonPropertyName("BackdropUrl")] string? BackdropUrl,
    [property: JsonPropertyName("JellyfinSeriesId")] string? JellyfinSeriesId);

/// <summary>Risposta di GET Upcoming/Series: con un errore Items è vuoto (sempre 200).</summary>
public sealed record UpcomingSeriesResponse(
    [property: JsonPropertyName("Items")] IReadOnlyList<UpcomingEpisodeDto> Items,
    [property: JsonPropertyName("Error")] string? Error);

/// <summary>Un film di GET Upcoming/Movies.</summary>
public sealed record UpcomingMovieDto(
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("DigitalRelease")] DateTimeOffset DigitalRelease,
    [property: JsonPropertyName("PosterUrl")] string? PosterUrl,
    [property: JsonPropertyName("BackdropUrl")] string? BackdropUrl);

/// <summary>Risposta di GET Upcoming/Movies: con un errore Items è vuoto (sempre 200).</summary>
public sealed record UpcomingMoviesResponse(
    [property: JsonPropertyName("Items")] IReadOnlyList<UpcomingMovieDto> Items,
    [property: JsonPropertyName("Error")] string? Error);

/// <summary>L'esito della prova di un servizio.</summary>
public sealed record ArrTestResult(
    [property: JsonPropertyName("Configured")] bool Configured,
    [property: JsonPropertyName("Ok")] bool Ok,
    [property: JsonPropertyName("Version")] string? Version,
    [property: JsonPropertyName("Error")] string? Error);

/// <summary>Risposta di POST Upcoming/Test (spec M §7.5).</summary>
public sealed record UpcomingTestResponse(
    [property: JsonPropertyName("Sonarr")] ArrTestResult Sonarr,
    [property: JsonPropertyName("Radarr")] ArrTestResult Radarr);
