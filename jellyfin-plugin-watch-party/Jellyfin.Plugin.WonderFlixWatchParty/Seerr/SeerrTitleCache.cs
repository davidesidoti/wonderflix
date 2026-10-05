using System.Collections.Concurrent;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Titolo, anno e locandina di un titolo TMDB.</summary>
public sealed record SeerrTitle(string Title, int? Year, string? PosterPath);

/// <summary>
/// I titoli degli elenchi delle richieste, che Seerr non dà (spec I §7.2):
/// per tipo, id TMDB e lingua, per <see cref="CacheFor"/>, al massimo
/// <see cref="MaxEntries"/>. Un titolo che Seerr non conosce (404) si ricorda
/// per <see cref="MissCacheFor"/>; gli altri errori (Seerr giù, chiave
/// rifiutata) non si ricordano. Le letture da Seerr sono al massimo
/// <see cref="MaxParallelLookups"/> insieme. Sicuro tra thread.
/// </summary>
public sealed class SeerrTitleCache(ISeerrClient seerr, TimeProvider time)
{
    /// <summary>Quanto vale un titolo letto.</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromHours(1);

    /// <summary>Quanto si ricorda che Seerr non ha un titolo, prima di chiederlo di nuovo.</summary>
    public static readonly TimeSpan MissCacheFor = TimeSpan.FromMinutes(5);

    /// <summary>Titoli al massimo in memoria; oltre si ricomincia da capo.</summary>
    public const int MaxEntries = 2000;

    /// <summary>Chiamate a Seerr per i titoli al massimo insieme; le altre aspettano il loro turno.</summary>
    public const int MaxParallelLookups = 6;

    private readonly ConcurrentDictionary<(string MediaType, int TmdbId, string Language), Entry> _titles = new();
    private readonly SemaphoreSlim _lookups = new(MaxParallelLookups, MaxParallelLookups);

    /// <summary>Il titolo; null se Seerr non lo dà o non risponde (l'elenco va avanti senza).</summary>
    public async Task<SeerrTitle?> GetAsync(
        string mediaType, int tmdbId, string language, CancellationToken cancellationToken)
    {
        var key = (mediaType, tmdbId, language);
        if (Fresh(key) is { } hit)
        {
            return hit.Title;
        }

        await _lookups.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            // Mentre aspettavo il turno un'altra riga può aver già letto lo stesso titolo.
            if (Fresh(key) is { } again)
            {
                return again.Title;
            }

            SeerrTitle title;
            try
            {
                title = mediaType == RequestMediaTypes.Tv
                    ? From(await seerr.GetTvAsync(tmdbId, language, cancellationToken).ConfigureAwait(false))
                    : From(await seerr.GetMovieAsync(tmdbId, language, cancellationToken).ConfigureAwait(false));
            }
            catch (SeerrException ex) when (ex.Error == SeerrError.NotFound)
            {
                // Titolo che Seerr non conosce: si ricorda per poco, senza chiederlo a Seerr a ogni riga.
                Store(key, null);
                return null;
            }
            catch (SeerrException)
            {
                // Seerr non risponde o rifiuta: non vuol dire che il titolo manchi, quindi non si
                // ricorda e alla prossima riga si riprova.
                return null;
            }

            Store(key, title);
            return title;
        }
        finally
        {
            _lookups.Release();
        }
    }

    /// <summary>Mette in memoria un titolo appena letto (dalle schede).</summary>
    public void Put(string mediaType, int tmdbId, string language, SeerrTitle title) =>
        Store((mediaType, tmdbId, language), title);

    public static SeerrTitle From(SeerrMovie movie) =>
        new(movie.Title ?? string.Empty, SeerrMapping.Year(movie.ReleaseDate), movie.PosterPath);

    public static SeerrTitle From(SeerrTv tv) =>
        new(tv.Name ?? string.Empty, SeerrMapping.Year(tv.FirstAirDate), tv.PosterPath);

    // La voce ancora valida: un titolo letto vale CacheFor, uno mancante MissCacheFor.
    private Entry? Fresh((string MediaType, int TmdbId, string Language) key) =>
        _titles.TryGetValue(key, out var entry)
        && time.GetUtcNow() - entry.At < (entry.Title is null ? MissCacheFor : CacheFor)
            ? entry
            : null;

    private void Store((string MediaType, int TmdbId, string Language) key, SeerrTitle? title)
    {
        if (_titles.Count >= MaxEntries)
        {
            _titles.Clear();
        }

        _titles[key] = new Entry(title, time.GetUtcNow());
    }

    // Title null = Seerr non ha il titolo.
    private sealed record Entry(SeerrTitle? Title, DateTimeOffset At);
}
