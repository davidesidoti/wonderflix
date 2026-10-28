using System.Text.Json;
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Il JSON di Sonarr e Radarr: nomi in camelCase, letti senza badare alle maiuscole.</summary>
internal static class ArrJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
}

/// <summary>Un numero intero che Radarr/Sonarr scrivono come decimal (size, sizeleft della coda): arrotondato (spec T §2).</summary>
internal sealed class RoundedLongConverter : JsonConverter<long>
{
    public override long Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.TryGetInt64(out var value) ? value : (long)Math.Round(reader.GetDouble(), MidpointRounding.AwayFromZero);

    public override void Write(Utf8JsonWriter writer, long value, JsonSerializerOptions options) => writer.WriteNumberValue(value);
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
    /// <summary>L'id della serie in Sonarr (0 nel calendario con includeSeries).</summary>
    public int Id { get; set; }

    /// <summary>Il prossimo episodio in onda; null se Sonarr non ne conosce.</summary>
    public DateTimeOffset? NextAiring { get; set; }

    public string? Title { get; set; }

    public int TvdbId { get; set; }

    public int TmdbId { get; set; }

    public string? ImdbId { get; set; }

    // Un null esplicito nel JSON vince sull'inizializzatore: niente "= []".
    public List<ArrImage?>? Images { get; set; }

    /// <summary>Durata di un episodio in minuti (0 se Sonarr non la sa) (spec T §2).</summary>
    public int Runtime { get; set; }

    /// <summary>Il profilo di qualità della serie (spec T §2).</summary>
    public int QualityProfileId { get; set; }

    /// <summary>Lo stato della serie ("continuing", "ended", ...) (spec T §2).</summary>
    public string? Status { get; set; }

    /// <summary>I conteggi della serie; null se Sonarr non li manda (spec T §2).</summary>
    public SonarrSeriesStatistics? Statistics { get; set; }
}

/// <summary>I conteggi di una serie di Sonarr (spec T §2).</summary>
public sealed class SonarrSeriesStatistics
{
    /// <summary>Gli episodi che hanno un file.</summary>
    public int EpisodeFileCount { get; set; }
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

    /// <summary>L'id dell'episodio in Sonarr (spec T §2).</summary>
    public int Id { get; set; }

    public bool Monitored { get; set; }

    /// <summary>L'id del file dell'episodio; 0 se non c'è (spec T §2).</summary>
    public int EpisodeFileId { get; set; }
}

/// <summary>Un film del calendario di Radarr.</summary>
public sealed class RadarrMovie
{
    public string? Title { get; set; }

    public int Year { get; set; }

    public int TmdbId { get; set; }

    /// <summary>Null se Radarr non conosce l'uscita digitale.</summary>
    public DateTimeOffset? DigitalRelease { get; set; }

    /// <summary>Null se Radarr non conosce l'uscita al cinema.</summary>
    public DateTimeOffset? InCinemas { get; set; }

    /// <summary>Null se Radarr non conosce l'uscita in supporto fisico.</summary>
    public DateTimeOffset? PhysicalRelease { get; set; }

    public bool HasFile { get; set; }

    public List<ArrImage?>? Images { get; set; }

    /// <summary>L'id del film in Radarr (spec T §2).</summary>
    public int Id { get; set; }

    /// <summary>Durata in minuti (0 se Radarr non la sa) (spec T §2).</summary>
    public int Runtime { get; set; }

    public bool Monitored { get; set; }

    /// <summary>Se il film è già uscito secondo Radarr (spec T §2).</summary>
    public bool IsAvailable { get; set; }

    public int QualityProfileId { get; set; }

    /// <summary>Il file del film; null se non c'è (spec T §2).</summary>
    public ArrFileRef? MovieFile { get; set; }
}

/// <summary>Un oggetto di cui serve solo l'id: il file di un film, il film, la serie o un episodio di <c>manualimport</c> (spec T §2).</summary>
public sealed class ArrFileRef
{
    public int Id { get; set; }
}

/// <summary>Una qualità di Sonarr o Radarr; Resolution è l'altezza in pixel (spec T §2).</summary>
public sealed class ArrQuality
{
    public int Id { get; set; }

    public string? Name { get; set; }

    public int Resolution { get; set; }
}

/// <summary>Il <c>quality</c> di una release o di un file: la qualità dentro un involucro (spec T §2).</summary>
public sealed class ArrQualityModel
{
    public ArrQuality? Quality { get; set; }
}

/// <summary>Una release trovata da una ricerca di Radarr o Sonarr (spec T §2).</summary>
public sealed class ArrRelease
{
    public string? Guid { get; set; }

    public int IndexerId { get; set; }

    public string? Indexer { get; set; }

    public string? Title { get; set; }

    public long Size { get; set; }

    /// <summary>Null per un indexer che non li dichiara (Usenet).</summary>
    public int? Seeders { get; set; }

    public ArrQualityModel? Quality { get; set; }

    public int CustomFormatScore { get; set; }

    /// <summary>Se Radarr o Sonarr la scarterebbero.</summary>
    public bool Rejected { get; set; }

    public List<string>? Rejections { get; set; }

    /// <summary>Solo Sonarr: un pack di stagione intera.</summary>
    public bool FullSeason { get; set; }

    /// <summary>Solo Sonarr: gli episodi coperti dalla release.</summary>
    public List<int>? EpisodeNumbers { get; set; }

    public int SeasonNumber { get; set; }
}

/// <summary>Una voce del profilo: una qualità sola (Quality) o un gruppo (Name e Items) (spec T §2).</summary>
public sealed class ArrQualityProfileItem
{
    public string? Name { get; set; }

    public ArrQuality? Quality { get; set; }

    public List<ArrQualityProfileItem>? Items { get; set; }

    public bool Allowed { get; set; }
}

/// <summary>Un profilo di qualità; gli Items vanno dal più basso al più alto (spec T §2).</summary>
public sealed class ArrQualityProfile
{
    public int Id { get; set; }

    public string? Name { get; set; }

    public List<ArrQualityProfileItem>? Items { get; set; }
}

/// <summary>Una voce della coda di Radarr o Sonarr (spec T §2).</summary>
public sealed class ArrQueueItem
{
    public int Id { get; set; }

    /// <summary>Solo Radarr.</summary>
    public int? MovieId { get; set; }

    /// <summary>Solo Sonarr.</summary>
    public int? EpisodeId { get; set; }

    /// <summary>Solo Sonarr.</summary>
    public int? SeriesId { get; set; }

    /// <summary>Solo Sonarr.</summary>
    public int? SeasonNumber { get; set; }

    public string? DownloadId { get; set; }

    /// <summary>Un decimal in Radarr/Sonarr: un valore con la virgola si arrotonda, non rompe la lettura della coda.</summary>
    [JsonConverter(typeof(RoundedLongConverter))]
    public long Size { get; set; }

    /// <summary>Come <see cref="Size"/>.</summary>
    [JsonConverter(typeof(RoundedLongConverter))]
    public long Sizeleft { get; set; }

    /// <summary>"downloading", "importBlocked", "importPending", "failed", ...</summary>
    public string? TrackedDownloadState { get; set; }

    /// <summary>Lo stato nel client: "downloading", "queued", "paused", "delay", "downloadClientUnavailable", "completed", "warning", ...</summary>
    public string? Status { get; set; }
}

/// <summary>Un file di un film (Radarr <c>moviefile</c>) o di un episodio (Sonarr <c>episodefile</c>) (spec T §2).</summary>
public sealed class ArrFile
{
    public int Id { get; set; }

    /// <summary>Solo Radarr.</summary>
    public int MovieId { get; set; }

    /// <summary>Solo Sonarr.</summary>
    public int SeasonNumber { get; set; }

    public int CustomFormatScore { get; set; }

    public long Size { get; set; }

    public ArrQualityModel? Quality { get; set; }
}

/// <summary>
/// Un file di <c>manualimport</c> (decisione 9; campi verificati su Radarr e Sonarr il 2026-10-28). Quality e Languages
/// restano JSON: si rimandano uguali nel comando ManualImport.
/// </summary>
public sealed class ArrManualImportItem
{
    public string? Path { get; set; }

    public JsonElement? Quality { get; set; }

    public JsonElement? Languages { get; set; }

    public string? ReleaseGroup { get; set; }

    public string? DownloadId { get; set; }

    /// <summary>Il peso del file: di un film si importa solo il più grande (ruling 14).</summary>
    public long Size { get; set; }

    /// <summary>Solo Radarr: il film riconosciuto; null se Radarr non l'ha riconosciuto.</summary>
    public ArrFileRef? Movie { get; set; }

    /// <summary>Solo Sonarr.</summary>
    public ArrFileRef? Series { get; set; }

    /// <summary>Solo Sonarr: gli episodi del file.</summary>
    public List<ArrFileRef?>? Episodes { get; set; }

    public List<ArrRejection?>? Rejections { get; set; }
}

/// <summary>Un motivo per cui Radarr/Sonarr non importerebbero un file di <c>manualimport</c> (decisione 9).</summary>
public sealed class ArrRejection
{
    public string? Reason { get; set; }
}

/// <summary>Un indexer; Priority più bassa = preferito (spec T §2).</summary>
public sealed class ArrIndexer
{
    public int Id { get; set; }

    public int Priority { get; set; }
}

/// <summary>Una pagina di una risposta con <c>page</c> e <c>pageSize</c> (<c>queue</c>, <c>wanted/missing</c>).</summary>
public sealed class ArrPage<T>
{
    public int TotalRecords { get; set; }

    public List<T?>? Records { get; set; }
}

/// <summary>Risposta di system/status.</summary>
public sealed class ArrStatus
{
    public string? AppName { get; set; }

    public string? Version { get; set; }
}
