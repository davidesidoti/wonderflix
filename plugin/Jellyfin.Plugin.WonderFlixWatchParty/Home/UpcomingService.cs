using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Una lettura di Sonarr o Radarr: le uscite, oppure un codice d'errore e nessuna uscita.</summary>
internal sealed record Fetched<T>(IReadOnlyList<T> Items, string? Error);

/// <summary>
/// Le uscite in arrivo per la Home (spec M §7.3, §7.4). Le risposte di
/// Sonarr e Radarr, già filtrate, valgono per tutti e restano in memoria 15
/// minuti (un errore 1 minuto); la serie di Jellyfin si sceglie per ogni
/// utente, tra quelle che vede. La cache è legata alle impostazioni: se
/// l'admin cambia indirizzo, chiave o giorni, la richiesta dopo rilegge.
/// </summary>
public sealed class UpcomingService(
    IArrClient client,
    IArrSettings settings,
    ISeriesIndex seriesIndex,
    ILibraryAccess library,
    TimeProvider time,
    ILogger<UpcomingService> logger)
{
    /// <summary>Quanto vale una risposta riuscita.</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromMinutes(15);

    /// <summary>Quanto vale un errore: abbastanza per non insistere su un servizio fermo.</summary>
    public static readonly TimeSpan ErrorCacheFor = TimeSpan.FromMinutes(1);

    /// <summary>Gli episodi usciti da poco e non ancora scaricati restano (quelli di stanotte).</summary>
    public static readonly TimeSpan SeriesLookBack = TimeSpan.FromHours(12);

    private readonly Lock _lock = new();
    private readonly Slot<UpcomingEpisodeGroup> _series = new();
    private readonly Slot<UpcomingMovie> _movies = new();

    public async Task<UpcomingSeriesResponse> GetSeriesAsync(Guid userId, CancellationToken cancellationToken)
    {
        var endpoint = settings.Sonarr;
        if (!endpoint.IsConfigured)
        {
            return new UpcomingSeriesResponse([], UpcomingErrors.NotConfigured);
        }

        var days = settings.SeriesDays;
        var fetched = await Cached(_series, Key(endpoint, days), () => FetchSeriesAsync(days))
            .WaitAsync(cancellationToken)
            .ConfigureAwait(false);
        return new UpcomingSeriesResponse(fetched.Items.Select(group => ToDto(group, userId)).ToList(), fetched.Error);
    }

    public async Task<UpcomingMoviesResponse> GetMoviesAsync(CancellationToken cancellationToken)
    {
        var endpoint = settings.Radarr;
        if (!endpoint.IsConfigured)
        {
            return new UpcomingMoviesResponse([], UpcomingErrors.NotConfigured);
        }

        var days = settings.MovieDays;
        var fetched = await Cached(_movies, Key(endpoint, days), () => FetchMoviesAsync(days))
            .WaitAsync(cancellationToken)
            .ConfigureAwait(false);
        return new UpcomingMoviesResponse(
            fetched.Items
                .Select(movie => new UpcomingMovieDto(
                    movie.Title, movie.Year, movie.TmdbId, movie.DigitalRelease, movie.PosterUrl, movie.BackdropUrl))
                .ToList(),
            fetched.Error);
    }

    /// <summary>"Prova collegamento" (spec M §7.5): lo stato di Sonarr e di Radarr insieme, senza cache.</summary>
    public async Task<UpcomingTestResponse> TestAsync(CancellationToken cancellationToken)
    {
        var sonarr = TestOneAsync(ArrKind.Sonarr, cancellationToken);
        var radarr = TestOneAsync(ArrKind.Radarr, cancellationToken);
        return new UpcomingTestResponse(await sonarr.ConfigureAwait(false), await radarr.ConfigureAwait(false));
    }

    // Le impostazioni che decidono la risposta; la chiave resta solo in memoria, mai nel log.
    private static string Key(ArrEndpoint endpoint, int days) => $"{endpoint.Url}\n{endpoint.ApiKey}\n{days}";

    private async Task<ArrTestResult> TestOneAsync(ArrKind kind, CancellationToken cancellationToken)
    {
        if (!settings.Endpoint(kind).IsConfigured)
        {
            return new ArrTestResult(false, false, null, UpcomingErrors.NotConfigured);
        }

        try
        {
            var status = await client.GetStatusAsync(kind, cancellationToken).ConfigureAwait(false);

            // Con gli indirizzi scambiati (Sonarr dove va Radarr) lo stato risponde lo stesso:
            // senza guardare chi risponde la prova direbbe "collegato" e le due righe resterebbero
            // vuote in silenzio. Un nome mancante vale come un'altra app.
            if (!string.Equals(status.AppName, kind.ToString(), StringComparison.OrdinalIgnoreCase))
            {
                logger.LogInformation(
                    "Prova di {Kind}: all'indirizzo risponde {AppName}", kind, status.AppName ?? "un'app senza nome");
                return new ArrTestResult(true, false, null, UpcomingErrors.Unreachable);
            }

            return new ArrTestResult(true, true, status.Version, null);
        }
        catch (ArrException ex)
        {
            return new ArrTestResult(true, false, null, UpcomingErrors.Code(ex.Error));
        }
    }

    private async Task<Fetched<UpcomingEpisodeGroup>> FetchSeriesAsync(int days)
    {
        var now = time.GetUtcNow();
        var from = now - SeriesLookBack;
        var to = now.AddDays(days);
        try
        {
            var episodes = await client.GetEpisodesAsync(from, to, CancellationToken.None).ConfigureAwait(false);
            return new(UpcomingBuilder.MatchSeries(UpcomingBuilder.Episodes(episodes, from, to), ReadLibrarySeries()), null);
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Serie in arrivo: Sonarr non ha risposto ({Error})", ex.Error);
            return new([], UpcomingErrors.Code(ex.Error));
        }
    }

    private async Task<Fetched<UpcomingMovie>> FetchMoviesAsync(int days)
    {
        // Da oggi (mezzanotte UTC) alla fine del giorno "days": Radarr dà le date a mezzanotte.
        var from = new DateTimeOffset(time.GetUtcNow().UtcDateTime.Date, TimeSpan.Zero);
        var to = from.AddDays(days + 1);
        try
        {
            var movies = await client.GetMoviesAsync(from, to, CancellationToken.None).ConfigureAwait(false);
            return new(UpcomingBuilder.Movies(movies, from, to), null);
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Film in arrivo: Radarr non ha risposto ({Error})", ex.Error);
            return new([], UpcomingErrors.Code(ex.Error));
        }
    }

    // Senza la libreria le uscite restano, solo senza il collegamento alla serie.
    private IReadOnlyList<LibrarySeries> ReadLibrarySeries()
    {
        try
        {
            return seriesIndex.GetSeries();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Serie in arrivo: le serie della libreria non si leggono");
            return [];
        }
    }

    private UpcomingEpisodeDto ToDto(UpcomingEpisodeGroup group, Guid userId)
    {
        var seriesId = group.LibrarySeriesIds.FirstOrDefault(id => CanSee(userId, id));
        return new UpcomingEpisodeDto(
            group.SeriesName,
            group.SeasonNumber,
            group.EpisodeNumber,
            group.LastEpisodeNumber,
            group.EpisodeTitle,
            group.AirDateUtc,
            group.TvdbId,
            group.TmdbId,
            group.PosterUrl,
            group.BackdropUrl,
            seriesId == Guid.Empty ? null : seriesId.ToString("N"));
    }

    // Un errore della libreria toglie solo il collegamento alla serie, non l'uscita.
    private bool CanSee(Guid userId, Guid seriesId)
    {
        try
        {
            return library.CanSee(userId, seriesId);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Serie in arrivo: visibilità della serie non letta");
            return false;
        }
    }

    /// <summary>
    /// La lettura in cache se è per le stesse impostazioni e non è scaduta
    /// (una in corso vale sempre, una finita in errore mai); altrimenti una
    /// nuova, una sola anche con più richieste insieme. La lettura non usa il
    /// token di chi chiede.
    /// </summary>
    private Task<Fetched<T>> Cached<T>(Slot<T> slot, string key, Func<Task<Fetched<T>>> fetch)
    {
        lock (_lock)
        {
            // Una lettura finita in errore (es. il registro che si rompe nel catch) non ha scadenza: non si riusa.
            if (slot.Read is { } read && slot.Key == key
                && (!read.IsCompleted || (read.IsCompletedSuccessfully && time.GetUtcNow() < slot.ExpiresAt)))
            {
                return read;
            }

            slot.Key = key;
            slot.ExpiresAt = DateTimeOffset.MaxValue;
            // Su un altro thread: la fine della lettura rientra in _lock per la scadenza.
            slot.Read = Task.Run(() => FetchAndExpireAsync(slot, key, fetch));
            return slot.Read;
        }
    }

    private async Task<Fetched<T>> FetchAndExpireAsync<T>(Slot<T> slot, string key, Func<Task<Fetched<T>>> fetch)
    {
        Fetched<T> result;
        try
        {
            result = await fetch().ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            // Un errore inatteso non resta in cache per sempre: vale come un servizio irraggiungibile.
            logger.LogWarning(ex, "Uscite in arrivo non lette");
            result = new([], UpcomingErrors.Unreachable);
        }

        lock (_lock)
        {
            // Se intanto le impostazioni sono cambiate, lo slot è già di un'altra lettura.
            if (slot.Key == key)
            {
                slot.ExpiresAt = time.GetUtcNow() + (result.Error is null ? CacheFor : ErrorCacheFor);
            }
        }

        return result;
    }

    private sealed class Slot<T>
    {
        public string? Key { get; set; }

        public Task<Fetched<T>>? Read { get; set; }

        public DateTimeOffset ExpiresAt { get; set; }
    }
}
