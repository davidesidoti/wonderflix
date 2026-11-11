using System.Collections.Concurrent;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>Di cosa si cerca il trailer: un elemento della libreria, o un titolo TMDB (<paramref name="MediaType"/> "movie" o "tv").</summary>
public sealed record TrailerSubject(Guid? ItemId, string? MediaType, int? TmdbId);

/// <summary>Il video YouTube del trailer.</summary>
public sealed record ResolvedTrailer(string VideoId, string? Name);

/// <summary>
/// Trova il video YouTube del trailer: prima quello che Jellyfin ha già sull'elemento,
/// poi quello che Seerr (TMDB) dà per il titolo, in italiano. Le risposte di Seerr, "nessun
/// trailer" compreso, valgono <see cref="CacheFor"/>; gli errori di Seerr no. Sicuro tra thread.
/// </summary>
public sealed class TrailerResolver(
    ITrailerLibrary library, ISeerrClient seerr, ISeerrSettings settings, TimeProvider time)
{
    /// <summary>Quanto vale una risposta di Seerr, e quanto un id risolto conta come "uscito da qui".</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromHours(24);

    /// <summary>Voci al massimo per ciascuna memoria; oltre si ricomincia da capo.</summary>
    public const int MaxEntries = 2000;

    private const string Language = "it";

    // La chiave non ha l'utente: Find controlla ogni volta che l'elemento lo veda, e la risposta di Seerr è la stessa per tutti.
    private readonly ConcurrentDictionary<(string MediaType, int TmdbId), (string? VideoId, DateTimeOffset At)> _seerrAnswers = new();
    private readonly ConcurrentDictionary<string, DateTimeOffset> _resolved = new();

    public async Task<ResolvedTrailer?> ResolveAsync(Guid userId, TrailerSubject subject, CancellationToken cancellationToken)
    {
        var mediaType = subject.MediaType;
        var tmdbId = subject.TmdbId;
        if (subject.ItemId is { } itemId)
        {
            if (library.Find(userId, itemId) is not { } item)
            {
                return null;
            }

            if (item.RemoteTrailerUrls.Select(YouTubeId.FromUrl).FirstOrDefault(id => id is not null) is { } own)
            {
                return Remember(own);
            }

            (mediaType, tmdbId) = (item.MediaType, item.TmdbId);
        }

        if ((mediaType != RequestMediaTypes.Movie && mediaType != RequestMediaTypes.Tv)
            || tmdbId is not > 0
            || !settings.IsConfigured())
        {
            return null;
        }

        var key = (mediaType, tmdbId.Value);
        if (_seerrAnswers.TryGetValue(key, out var hit) && time.GetUtcNow() - hit.At < CacheFor)
        {
            return hit.VideoId is null ? null : Remember(hit.VideoId);
        }

        string? videoId;
        try
        {
            var videos = mediaType == RequestMediaTypes.Tv
                ? (await seerr.GetTvAsync(tmdbId.Value, Language, cancellationToken).ConfigureAwait(false)).RelatedVideos
                : (await seerr.GetMovieAsync(tmdbId.Value, Language, cancellationToken).ConfigureAwait(false)).RelatedVideos;
            videoId = YouTubeId.FromUrl(SeerrMapping.TrailerUrl(videos));
        }
        catch (SeerrException ex) when (ex.Error == SeerrError.NotFound)
        {
            videoId = null;
        }
        catch (Exception ex) when (ex is SeerrException or HttpRequestException or TimeoutException)
        {
            // Seerr giù o chiave rifiutata: non vuol dire che il trailer manchi, quindi non si ricorda.
            return null;
        }

        if (_seerrAnswers.Count >= MaxEntries)
        {
            _seerrAnswers.Clear();
        }

        _seerrAnswers[key] = (videoId, time.GetUtcNow());
        return videoId is null ? null : Remember(videoId);
    }

    /// <summary>Questo id l'ha dato di recente il risolutore: solo questi si scaricano.</summary>
    public bool WasResolved(string videoId) =>
        _resolved.TryGetValue(videoId, out var at) && time.GetUtcNow() - at < CacheFor;

    private ResolvedTrailer Remember(string videoId)
    {
        if (_resolved.Count >= MaxEntries)
        {
            _resolved.Clear();
        }

        _resolved[videoId] = time.GetUtcNow();
        return new ResolvedTrailer(videoId, null);
    }
}
