using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il finder finto per i test di DownloadService: risponde con un gestore e ricorda le chiamate.</summary>
internal sealed class FakeReleaseFinder : IReleaseFinder
{
    private readonly Lock _lock = new();

    public bool UsesProwlarr { get; set; }

    public Func<DownloadKey, SearchEngine, Task<FinderResult>> Search { get; set; } =
        (_, engine) => Task.FromResult(new FinderResult([], [], engine));

    public List<(DownloadKey Key, SearchEngine Engine, TimeSpan? Timeout)> SearchCalls { get; } = [];

    public Task<FinderResult> SearchAsync(DownloadKey key, SearchEngine engine, CancellationToken cancellationToken, TimeSpan? arrTimeout = null)
    {
        lock (_lock)
        {
            SearchCalls.Add((key, engine, arrTimeout));
        }

        return Search(key, engine);
    }
}
