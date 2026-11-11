using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Prowlarr finto: risponde con un gestore e conta le ricerche.</summary>
internal sealed class FakeProwlarrClient : IProwlarrClient
{
    private readonly Lock _lock = new();

    public Func<ProwlarrQuery, Task<IReadOnlyList<ProwlarrRelease>>> Search { get; set; } =
        _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>([]);

    public List<ProwlarrQuery> SearchCalls { get; } = [];

    public Task<IReadOnlyList<ProwlarrRelease>> SearchAsync(ProwlarrQuery query, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            SearchCalls.Add(query);
        }

        return Search(query);
    }
}
