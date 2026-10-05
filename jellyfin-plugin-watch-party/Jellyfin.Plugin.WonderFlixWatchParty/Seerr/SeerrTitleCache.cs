using System.Collections.Concurrent;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Titolo, anno e locandina di un titolo TMDB.</summary>
public sealed record SeerrTitle(string Title, int? Year, string? PosterPath);

/// <summary>
/// I titoli degli elenchi delle richieste, che Seerr non dà (spec I §7.2):
/// per tipo, id TMDB e lingua, per <see cref="CacheFor"/>, al massimo
/// <see cref="MaxEntries"/>. Sicuro tra thread.
/// </summary>
public sealed class SeerrTitleCache(ISeerrClient seerr, TimeProvider time)
{
    /// <summary>Quanto vale un titolo letto.</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromHours(1);

    /// <summary>Titoli al massimo in memoria; oltre si ricomincia da capo.</summary>
    public const int MaxEntries = 2000;

    private readonly ConcurrentDictionary<(string MediaType, int TmdbId, string Language), Entry> _titles = new();

    /// <summary>Il titolo; null se Seerr non lo dà (l'elenco va avanti senza).</summary>
    public async Task<SeerrTitle?> GetAsync(
        string mediaType, int tmdbId, string language, CancellationToken cancellationToken)
    {
        if (_titles.TryGetValue((mediaType, tmdbId, language), out var hit) && time.GetUtcNow() - hit.At < CacheFor)
        {
            return hit.Title;
        }

        SeerrTitle title;
        try
        {
            title = mediaType == RequestMediaTypes.Tv
                ? From(await seerr.GetTvAsync(tmdbId, language, cancellationToken).ConfigureAwait(false))
                : From(await seerr.GetMovieAsync(tmdbId, language, cancellationToken).ConfigureAwait(false));
        }
        catch (SeerrException)
        {
            return null;
        }

        Put(mediaType, tmdbId, language, title);
        return title;
    }

    /// <summary>Mette in memoria un titolo appena letto (dalle schede).</summary>
    public void Put(string mediaType, int tmdbId, string language, SeerrTitle title)
    {
        if (_titles.Count >= MaxEntries)
        {
            _titles.Clear();
        }

        _titles[(mediaType, tmdbId, language)] = new Entry(title, time.GetUtcNow());
    }

    public static SeerrTitle From(SeerrMovie movie) =>
        new(movie.Title ?? string.Empty, SeerrMapping.Year(movie.ReleaseDate), movie.PosterPath);

    public static SeerrTitle From(SeerrTv tv) =>
        new(tv.Name ?? string.Empty, SeerrMapping.Year(tv.FirstAirDate), tv.PosterPath);

    private sealed record Entry(SeerrTitle Title, DateTimeOffset At);
}
