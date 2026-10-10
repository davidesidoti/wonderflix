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

    public Func<ArrKind, Task<ArrStatus>> Status { get; set; } =
        kind => Task.FromResult(new ArrStatus { AppName = kind.ToString(), Version = "1.0" });

    public List<(DateTimeOffset From, DateTimeOffset To)> EpisodeCalls { get; } = [];

    public List<(DateTimeOffset From, DateTimeOffset To)> MovieCalls { get; } = [];

    public List<ArrKind> StatusCalls { get; } = [];

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
