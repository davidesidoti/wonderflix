using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Sonarr e Radarr finti: rispondono con i gestori e contano le chiamate.</summary>
internal sealed class FakeArrClient : IArrClient
{
    private readonly Lock _lock = new();

    public Func<DateTimeOffset, DateTimeOffset, Task<IReadOnlyList<SonarrEpisode?>>> Episodes { get; set; } =
        (_, _) => Task.FromResult<IReadOnlyList<SonarrEpisode?>>([]);

    public Func<DateTimeOffset, DateTimeOffset, Task<IReadOnlyList<RadarrMovie?>>> Movies { get; set; } =
        (_, _) => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);

    public Func<int, Task<IReadOnlyList<RadarrMovie?>>> FindMovies { get; set; } =
        _ => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);

    public Func<int, Task<RadarrMovie>> Lookup { get; set; } =
        _ => Task.FromException<RadarrMovie>(new ArrException(ArrError.Unreachable));

    public Func<Task<IReadOnlyList<SonarrSeries?>>> Series { get; set; } =
        () => Task.FromResult<IReadOnlyList<SonarrSeries?>>([]);

    public Func<int, Task<IReadOnlyList<SonarrEpisode?>>> SeriesEpisodes { get; set; } =
        _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>([]);

    public Func<ArrKind, Task<ArrStatus>> Status { get; set; } =
        kind => Task.FromResult(new ArrStatus { AppName = kind.ToString(), Version = "1.0" });

    public List<(DateTimeOffset From, DateTimeOffset To)> EpisodeCalls { get; } = [];

    public List<(DateTimeOffset From, DateTimeOffset To)> MovieCalls { get; } = [];

    public List<ArrKind> StatusCalls { get; } = [];

    public List<int> FindMovieCalls { get; } = [];

    public List<int> LookupCalls { get; } = [];

    public int SeriesCalls { get; private set; }

    public List<int> SeriesEpisodeCalls { get; } = [];

    public Task<IReadOnlyList<RadarrMovie?>> FindMoviesAsync(int tmdbId, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            FindMovieCalls.Add(tmdbId);
        }

        return FindMovies(tmdbId);
    }

    public Task<RadarrMovie> LookupMovieAsync(int tmdbId, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            LookupCalls.Add(tmdbId);
        }

        return Lookup(tmdbId);
    }

    public Task<IReadOnlyList<SonarrSeries?>> GetSeriesAsync(CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            SeriesCalls++;
        }

        return Series();
    }

    public Task<IReadOnlyList<SonarrEpisode?>> GetSeriesEpisodesAsync(int seriesId, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            SeriesEpisodeCalls.Add(seriesId);
        }

        return SeriesEpisodes(seriesId);
    }

    public Task<IReadOnlyList<SonarrEpisode?>> GetEpisodesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            EpisodeCalls.Add((from, to));
        }

        return Episodes(from, to);
    }

    public Task<IReadOnlyList<RadarrMovie?>> GetMoviesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            MovieCalls.Add((from, to));
        }

        return Movies(from, to);
    }

    public Task<ArrStatus> GetStatusAsync(ArrKind kind, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            StatusCalls.Add(kind);
        }

        return Status(kind);
    }

    // Le chiamate della spec T (download automatici): elenchi vuoti e successo, salvo gestori diversi.
    public Func<ArrKind, string, Task<IReadOnlyList<ArrRelease?>>> Releases { get; set; } =
        (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([]);

    public Func<ArrKind, string, int, Task> Grab { get; set; } = (_, _, _) => Task.CompletedTask;

    public Func<Task<IReadOnlyList<RadarrMovie?>>> LibraryMovies { get; set; } =
        () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);

    public Func<Task<IReadOnlyList<SonarrEpisode?>>> MissingEpisodes { get; set; } =
        () => Task.FromResult<IReadOnlyList<SonarrEpisode?>>([]);

    public Func<IReadOnlyList<int>, Task<IReadOnlyList<ArrFile?>>> MovieFiles { get; set; } =
        _ => Task.FromResult<IReadOnlyList<ArrFile?>>([]);

    public Func<int, Task<IReadOnlyList<ArrFile?>>> EpisodeFiles { get; set; } =
        _ => Task.FromResult<IReadOnlyList<ArrFile?>>([]);

    public Func<ArrKind, Task<IReadOnlyList<ArrQualityProfile?>>> QualityProfiles { get; set; } =
        _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([]);

    public Func<ArrKind, Task<IReadOnlyList<ArrQueueItem?>>> Queue { get; set; } =
        _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>([]);

    public Func<ArrKind, int, bool, Task> RemoveFromQueue { get; set; } = (_, _, _) => Task.CompletedTask;

    public Func<ArrKind, Task<IReadOnlyList<ArrIndexer?>>> Indexers { get; set; } =
        _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([]);

    public List<(ArrKind Kind, string Query)> SearchReleaseCalls { get; } = [];

    public List<(ArrKind Kind, string Guid, int IndexerId)> GrabCalls { get; } = [];

    public int LibraryMovieCalls { get; private set; }

    public int MissingEpisodeCalls { get; private set; }

    public List<IReadOnlyList<int>> MovieFileCalls { get; } = [];

    public List<int> EpisodeFileCalls { get; } = [];

    public List<ArrKind> QualityProfileCalls { get; } = [];

    public List<ArrKind> QueueCalls { get; } = [];

    public List<(ArrKind Kind, int QueueId, bool Blocklist)> RemoveFromQueueCalls { get; } = [];

    public List<ArrKind> IndexerCalls { get; } = [];

    public Task<IReadOnlyList<ArrRelease?>> SearchReleasesAsync(
        ArrKind kind, string query, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            SearchReleaseCalls.Add((kind, query));
        }

        return Releases(kind, query);
    }

    public Task GrabReleaseAsync(ArrKind kind, string guid, int indexerId, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            GrabCalls.Add((kind, guid, indexerId));
        }

        return Grab(kind, guid, indexerId);
    }

    public Task<IReadOnlyList<RadarrMovie?>> GetLibraryMoviesAsync(CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            LibraryMovieCalls++;
        }

        return LibraryMovies();
    }

    public Task<IReadOnlyList<SonarrEpisode?>> GetMissingEpisodesAsync(CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            MissingEpisodeCalls++;
        }

        return MissingEpisodes();
    }

    public Task<IReadOnlyList<ArrFile?>> GetMovieFilesAsync(
        IReadOnlyList<int> movieFileIds, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            MovieFileCalls.Add(movieFileIds);
        }

        return MovieFiles(movieFileIds);
    }

    public Task<IReadOnlyList<ArrFile?>> GetEpisodeFilesAsync(int seriesId, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            EpisodeFileCalls.Add(seriesId);
        }

        return EpisodeFiles(seriesId);
    }

    public Task<IReadOnlyList<ArrQualityProfile?>> GetQualityProfilesAsync(
        ArrKind kind, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            QualityProfileCalls.Add(kind);
        }

        return QualityProfiles(kind);
    }

    public Task<IReadOnlyList<ArrQueueItem?>> GetQueueAsync(ArrKind kind, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            QueueCalls.Add(kind);
        }

        return Queue(kind);
    }

    public Task RemoveFromQueueAsync(ArrKind kind, int queueId, bool blocklist, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            RemoveFromQueueCalls.Add((kind, queueId, blocklist));
        }

        return RemoveFromQueue(kind, queueId, blocklist);
    }

    public Task<IReadOnlyList<ArrIndexer?>> GetIndexersAsync(ArrKind kind, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            IndexerCalls.Add(kind);
        }

        return Indexers(kind);
    }
}
