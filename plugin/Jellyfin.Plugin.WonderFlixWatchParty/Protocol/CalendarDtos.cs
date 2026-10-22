using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un episodio, o un blocco di episodi, di GET Upcoming/Calendar (spec S §6.1). OnServer: già scaricato.</summary>
public sealed record CalendarEpisodeDto(
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
    [property: JsonPropertyName("JellyfinSeriesId")] string? JellyfinSeriesId,
    [property: JsonPropertyName("OnServer")] bool OnServer);

/// <summary>Un film di GET Upcoming/Calendar (spec S §6.1).</summary>
public sealed record CalendarMovieDto(
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("DigitalRelease")] DateTimeOffset DigitalRelease,
    [property: JsonPropertyName("PosterUrl")] string? PosterUrl,
    [property: JsonPropertyName("BackdropUrl")] string? BackdropUrl,
    [property: JsonPropertyName("JellyfinItemId")] string? JellyfinItemId,
    [property: JsonPropertyName("OnServer")] bool OnServer);

/// <summary>Risposta di GET Upcoming/Calendar: sempre 200, un servizio in errore svuota solo la sua lista.</summary>
public sealed record CalendarResponse(
    [property: JsonPropertyName("Episodes")] IReadOnlyList<CalendarEpisodeDto> Episodes,
    [property: JsonPropertyName("Movies")] IReadOnlyList<CalendarMovieDto> Movies,
    [property: JsonPropertyName("SeriesError")] string? SeriesError,
    [property: JsonPropertyName("MoviesError")] string? MoviesError);
