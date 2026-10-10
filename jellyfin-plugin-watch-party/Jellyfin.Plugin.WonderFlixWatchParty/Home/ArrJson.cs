using System.Text.Json;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Il JSON di Sonarr e Radarr: nomi in camelCase, letti senza badare alle maiuscole.</summary>
internal static class ArrJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
}

/// <summary>Un'immagine: remoteUrl è l'indirizzo pubblico (TVDB, TMDB, Fanart).</summary>
public sealed class ArrImage
{
    public string? CoverType { get; set; }

    public string? RemoteUrl { get; set; }
}

/// <summary>La serie di un episodio del calendario di Sonarr (includeSeries=true).</summary>
public sealed class SonarrSeries
{
    public string? Title { get; set; }

    public int TvdbId { get; set; }

    public int TmdbId { get; set; }

    public string? ImdbId { get; set; }

    // Un null esplicito nel JSON vince sull'inizializzatore: niente "= []".
    public List<ArrImage?>? Images { get; set; }
}

/// <summary>Un episodio del calendario di Sonarr.</summary>
public sealed class SonarrEpisode
{
    public int SeriesId { get; set; }

    public int SeasonNumber { get; set; }

    public int EpisodeNumber { get; set; }

    public string? Title { get; set; }

    /// <summary>Null per un episodio senza data.</summary>
    public DateTimeOffset? AirDateUtc { get; set; }

    public bool HasFile { get; set; }

    public SonarrSeries? Series { get; set; }
}

/// <summary>Un film del calendario di Radarr.</summary>
public sealed class RadarrMovie
{
    public string? Title { get; set; }

    public int Year { get; set; }

    public int TmdbId { get; set; }

    /// <summary>Null se Radarr non conosce l'uscita digitale.</summary>
    public DateTimeOffset? DigitalRelease { get; set; }

    public bool HasFile { get; set; }

    public List<ArrImage?>? Images { get; set; }
}

/// <summary>Risposta di system/status.</summary>
public sealed class ArrStatus
{
    public string? AppName { get; set; }

    public string? Version { get; set; }
}
