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
}
