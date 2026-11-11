using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

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

    /// <summary>L'anno della prima stagione; 0 se Sonarr non lo sa (spec U §5.1).</summary>
    public int Year { get; set; }

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

    /// <summary>La serie è monitorata: senza, "Cerca un upgrade" non vale per le sue stagioni.</summary>
    public bool Monitored { get; set; }

    /// <summary>I conteggi della serie; null se Sonarr non li manda (spec T §2).</summary>
    public SonarrSeriesStatistics? Statistics { get; set; }

    /// <summary>La cartella della serie sul disco di Sonarr (spec U).</summary>
    public string? Path { get; set; }

    public DateTimeOffset? Added { get; set; }

    /// <summary>Le stagioni, con monitoraggio e dimensione; gli elementi possono essere null (spec U).</summary>
    public List<SonarrSeason?>? Seasons { get; set; }

    /// <summary>"standard", "anime" o "daily".</summary>
    public string? SeriesType { get; set; }

    /// <summary>I titoli alternativi, anche di una sola stagione; gli elementi possono essere null.</summary>
    public List<SonarrAlternateTitle?>? AlternateTitles { get; set; }

    /// <summary>Gli id dei tag, per le regole di release che valgono solo per alcuni.</summary>
    public List<int>? Tags { get; set; }
}

/// <summary>Una stagione di una serie di Sonarr (spec U).</summary>
public sealed class SonarrSeason
{
    public int SeasonNumber { get; set; }

    public bool Monitored { get; set; }

    /// <summary>Null per una stagione senza conteggi.</summary>
    public SonarrSeasonStatistics? Statistics { get; set; }
}

/// <summary>I conteggi di una stagione di Sonarr (spec U).</summary>
public sealed class SonarrSeasonStatistics
{
    public int EpisodeFileCount { get; set; }

    public long SizeOnDisk { get; set; }
}

/// <summary>I conteggi di una serie di Sonarr (spec T §2).</summary>
public sealed class SonarrSeriesStatistics
{
    /// <summary>Gli episodi che hanno un file.</summary>
    public int EpisodeFileCount { get; set; }

    /// <summary>I byte occupati dai file della serie (spec U).</summary>
    public long SizeOnDisk { get; set; }
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

    /// <summary>La numerazione assoluta (anime); null se non c'è.</summary>
    public int? AbsoluteEpisodeNumber { get; set; }

    public int? SceneAbsoluteEpisodeNumber { get; set; }

    public int? SceneSeasonNumber { get; set; }

    public int? SceneEpisodeNumber { get; set; }
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

    /// <summary>I byte occupati dal file del film (spec U).</summary>
    public long SizeOnDisk { get; set; }

    public DateTimeOffset? Added { get; set; }

    /// <summary>La cartella del film sul disco di Radarr (spec U).</summary>
    public string? Path { get; set; }

    /// <summary>"announced", "inCinemas" o "released" (spec U).</summary>
    public string? Status { get; set; }

    /// <summary>La collezione del film; null se non ne ha una (spec U).</summary>
    public ArrCollection? Collection { get; set; }

    public string? OriginalTitle { get; set; }

    public ArrLanguage? OriginalLanguage { get; set; }

    /// <summary>I titoli alternativi; gli elementi possono essere null.</summary>
    public List<RadarrAlternateTitle?>? AlternateTitles { get; set; }

    /// <summary>Gli id dei tag, per le regole di release che valgono solo per alcuni.</summary>
    public List<int>? Tags { get; set; }
}

/// <summary>La collezione di un film di Radarr (spec U).</summary>
public sealed class ArrCollection
{
    public int TmdbId { get; set; }

    public string? Title { get; set; }
}

/// <summary>Un oggetto di cui serve solo l'id: il file di un film, il film, la serie o un episodio di <c>manualimport</c> (spec T §2).</summary>
public sealed class ArrFileRef
{
    public int Id { get; set; }

    /// <summary>Solo per il file di un film (spec U).</summary>
    public string? Path { get; set; }

    /// <summary>Solo per il file di un film (spec U).</summary>
    public long Size { get; set; }

    /// <summary>Solo per il file di un film: quando Radarr l'ha importato (piano 30d).</summary>
    public DateTimeOffset? DateAdded { get; set; }
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

    /// <summary>Solo Sonarr: gli episodi della stagione, anche per una release numerata in assoluto (anime).</summary>
    public List<int>? MappedEpisodeNumbers { get; set; }

    /// <summary>Gli episodi della stagione che la release copre: quelli mappati di Sonarr, se ci sono.</summary>
    [JsonIgnore]
    public List<int>? SeasonEpisodeNumbers => MappedEpisodeNumbers is { Count: > 0 } ? MappedEpisodeNumbers : EpisodeNumbers;

    public int SeasonNumber { get; set; }

    /// <summary>Da dove viene: Sonarr/Radarr stessi o Prowlarr (i campi sotto servono solo a quest'ultimo).</summary>
    [JsonIgnore]
    public ReleaseSource Source { get; set; }

    /// <summary>Il .torrent da scaricare tramite Prowlarr; null per chi dà solo il magnet.</summary>
    [JsonIgnore]
    public string? DownloadUrl { get; set; }

    [JsonIgnore]
    public string? MagnetUrl { get; set; }

    /// <summary>"torrent" o "usenet".</summary>
    [JsonIgnore]
    public string? Protocol { get; set; }

    [JsonIgnore]
    public DateTimeOffset? PublishDate { get; set; }

    /// <summary>Non null = il parse l'attribuisce ad altro: testo breve per il log.</summary>
    [JsonIgnore]
    public string? WrongTitle { get; set; }
}

/// <summary>Chi ha trovato la release.</summary>
public enum ReleaseSource
{
    Arr,
    Prowlarr,
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

    /// <summary>Il punteggio minimo dei formati personalizzati: sotto, la release è scartata.</summary>
    public int MinFormatScore { get; set; }
}

/// <summary>Una voce della coda di Radarr o Sonarr (spec T §2).</summary>
public sealed class ArrQueueItem
{
    public int Id { get; set; }

    /// <summary>Il nome del download.</summary>
    public string? Title { get; set; }

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

    /// <summary>"ok", "warning", "error".</summary>
    public string? TrackedDownloadStatus { get; set; }

    /// <summary>Lo stato nel client: "downloading", "queued", "paused", "delay", "downloadClientUnavailable", "completed", "warning", ...</summary>
    public string? Status { get; set; }

    /// <summary>Il messaggio del client, per esempio "qBittorrent is downloading metadata" mentre il magnet non si risolve.</summary>
    public string? ErrorMessage { get; set; }

    /// <summary>Quando Radarr/Sonarr stimano la fine del download; assente se non lo sanno.</summary>
    public DateTimeOffset? EstimatedCompletionTime { get; set; }

    /// <summary>Quando il download è stato preso (<c>added</c>); da lì il client cerca i metadati del magnet.</summary>
    public DateTimeOffset? Added { get; set; }

    /// <summary>Perché Radarr/Sonarr non importano o avvisano, per file.</summary>
    public List<ArrStatusMessage?>? StatusMessages { get; set; }
}

/// <summary>Un gruppo di <c>statusMessages</c> di una voce della coda: il file e i suoi messaggi.</summary>
public sealed class ArrStatusMessage
{
    public string? Title { get; set; }

    public List<string?>? Messages { get; set; }
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

    /// <summary>Il percorso del file sul disco (spec U).</summary>
    public string? Path { get; set; }

    /// <summary>Quando Radarr o Sonarr l'ha importato (piano 30d).</summary>
    public DateTimeOffset? DateAdded { get; set; }
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

    /// <summary>Solo Sonarr: la stagione del file, per scegliere quelli di una stagione in un pack.</summary>
    public int? SeasonNumber { get; set; }

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
    private static readonly Regex ProwlarrPath = new(@"/prowlarr/(\d+)/", RegexOptions.CultureInvariant);

    public int Id { get; set; }

    public int Priority { get; set; }

    public string? Name { get; set; }

    public bool EnableInteractiveSearch { get; set; }

    /// <summary>I campi dell'indexer (<c>baseUrl</c>, <c>categories</c>, ...); gli elementi possono essere null.</summary>
    public List<ArrField?>? Fields { get; set; }

    /// <summary>L'id dell'indexer in Prowlarr, dal <c>baseUrl</c> (<c>.../prowlarr/11/</c>); null per un indexer che non viene da lì.</summary>
    [JsonIgnore]
    public int? ProwlarrId =>
        Field("baseUrl") is { ValueKind: JsonValueKind.String } url
        && ProwlarrPath.Match(url.GetString()!) is { Success: true } match
        && int.TryParse(match.Groups[1].Value, out var id)
            ? id
            : null;

    [JsonIgnore]
    public IReadOnlyList<int> Categories => Numbers("categories");

    [JsonIgnore]
    public IReadOnlyList<int> AnimeCategories => Numbers("animeCategories");

    [JsonIgnore]
    public int? MinimumSeeders =>
        Field("minimumSeeders") is { ValueKind: JsonValueKind.Number } n && n.TryGetInt32(out var value) ? value : null;

    private JsonElement? Field(string name) => Fields?.OfType<ArrField>().FirstOrDefault(f => f.Name == name)?.Value;

    private IReadOnlyList<int> Numbers(string name) =>
        Field(name) is { ValueKind: JsonValueKind.Array } array
            ? array.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.Number && e.TryGetInt32(out _)).Select(e => e.GetInt32()).ToList()
            : [];
}

/// <summary>Un client di download; per qBittorrent la categoria è il campo <c>tvCategory</c> (Sonarr) o <c>movieCategory</c> (Radarr).</summary>
public sealed class ArrDownloadClient
{
    public bool Enable { get; set; }

    public string? Implementation { get; set; }

    public List<ArrField?>? Fields { get; set; }

    [JsonIgnore]
    public string? Category =>
        Fields?.OfType<ArrField>().FirstOrDefault(f => f.Name is "tvCategory" or "movieCategory")?.Value is { ValueKind: JsonValueKind.String } value
            ? value.GetString()
            : null;
}

/// <summary>Un campo di un indexer: nome e valore (numero, testo o lista, quindi JSON).</summary>
public sealed class ArrField
{
    public string? Name { get; set; }

    public JsonElement? Value { get; set; }
}

/// <summary>Un titolo alternativo di una serie di Sonarr; <c>SeasonNumber</c> -1 = vale per tutta la serie.</summary>
public sealed class SonarrAlternateTitle
{
    public string? Title { get; set; }

    public int? SeasonNumber { get; set; }

    public int? SceneSeasonNumber { get; set; }
}

/// <summary>Una lingua di Radarr (<c>originalLanguage</c>, lingua di un titolo alternativo).</summary>
public sealed class ArrLanguage
{
    public string? Name { get; set; }
}

/// <summary>Un titolo alternativo di un film di Radarr.</summary>
public sealed class RadarrAlternateTitle
{
    public string? Title { get; set; }

    public ArrLanguage? Language { get; set; }
}

/// <summary>Il risultato di <c>GET parse</c>: cosa Sonarr (<c>ParsedEpisodeInfo</c>, <c>Series</c>, <c>Episodes</c>) o Radarr (<c>ParsedMovieInfo</c>, <c>Movie</c>) capiscono da un titolo.</summary>
public sealed class ArrParse
{
    public ArrParsedInfo? ParsedEpisodeInfo { get; set; }

    public ArrParsedInfo? ParsedMovieInfo { get; set; }

    public SonarrSeries? Series { get; set; }

    public RadarrMovie? Movie { get; set; }

    public List<SonarrEpisode?>? Episodes { get; set; }

    public int CustomFormatScore { get; set; }
}

/// <summary>Quello che il parse ha letto dal titolo; i campi di stagione ed episodi solo per Sonarr.</summary>
public sealed class ArrParsedInfo
{
    public ArrQualityModel? Quality { get; set; }

    public bool FullSeason { get; set; }

    public int SeasonNumber { get; set; }

    public List<int>? EpisodeNumbers { get; set; }

    public List<int>? AbsoluteEpisodeNumbers { get; set; }
}

/// <summary>Una release trovata da Prowlarr, come la si manda a <c>release/push</c>; Protocol è "torrent" o "usenet".</summary>
public sealed class ArrPushRelease
{
    public string Title { get; set; } = string.Empty;

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? DownloadUrl { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? MagnetUrl { get; set; }

    public string Protocol { get; set; } = string.Empty;

    public DateTimeOffset PublishDate { get; set; }

    public long Size { get; set; }

    public int IndexerId { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? Seeders { get; set; }
}

/// <summary>La decisione di Sonarr/Radarr su una release spinta: presa (<c>Approved</c>), scartata (<c>Rejected</c>) o scartata per ora (<c>TemporarilyRejected</c>).</summary>
public sealed class ArrPushResult
{
    public bool Approved { get; set; }

    public bool TemporarilyRejected { get; set; }

    public bool Rejected { get; set; }

    public List<string>? Rejections { get; set; }
}

/// <summary>Il peso ammesso per una qualità, in MB per minuto; <c>MaxSize</c> null = senza limite.</summary>
public sealed class ArrQualityDefinition
{
    public ArrQuality? Quality { get; set; }

    public double? MinSize { get; set; }

    public double? MaxSize { get; set; }
}

/// <summary>Una regola di release: termini obbligatori e vietati, valida per le serie/film con questi tag (o per tutti, se senza).</summary>
public sealed class ArrReleaseProfile
{
    public bool Enabled { get; set; }

    [JsonConverter(typeof(StringOrListConverter))]
    public List<string>? Required { get; set; }

    [JsonConverter(typeof(StringOrListConverter))]
    public List<string>? Ignored { get; set; }

    public List<int>? Tags { get; set; }
}

/// <summary>Un elenco di testi che le versioni vecchie scrivono come un testo solo, con le virgole.</summary>
internal sealed class StringOrListConverter : JsonConverter<List<string>>
{
    public override List<string>? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.TokenType == JsonTokenType.String
            ? reader.GetString()!.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList()
            : JsonSerializer.Deserialize<List<string>>(ref reader, options);

    public override void Write(Utf8JsonWriter writer, List<string> value, JsonSerializerOptions options) =>
        JsonSerializer.Serialize(writer, value, options);
}

/// <summary>Una release in blocklist di Sonarr (<c>SeriesId</c>) o Radarr (<c>MovieId</c>).</summary>
public sealed class ArrBlocklistItem
{
    public string? SourceTitle { get; set; }

    public string? Indexer { get; set; }

    public int? SeriesId { get; set; }

    public int? MovieId { get; set; }
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
