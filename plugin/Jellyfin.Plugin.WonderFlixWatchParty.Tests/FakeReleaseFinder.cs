using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

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

    public Func<ArrKind, ArrRelease, bool, Task<GrabResult>> Grab { get; set; } =
        (_, _, _) => Task.FromResult(new GrabResult(GrabKind.Grabbed, null, null));

    public List<(ArrKind Service, ArrRelease Release, bool Intentional, bool OutsideProfile)> GrabCalls { get; } = [];

    /// <summary>Se c'è, il grab va davvero in questo finder (con tutti i parametri) invece che in <see cref="Grab"/>.</summary>
    public IReleaseFinder? Real { get; set; }

    public Task<GrabResult> GrabAsync(ArrKind service, ArrRelease release, bool intentional, CancellationToken cancellationToken, bool outsideProfile = false)
    {
        lock (_lock)
        {
            GrabCalls.Add((service, release, intentional, outsideProfile));
        }

        return Real?.GrabAsync(service, release, intentional, cancellationToken, outsideProfile) ?? Grab(service, release, intentional);
    }

    public Func<ArrKind, ArrRelease, Task<string>> AddDirect { get; set; } = (_, _) => Task.FromResult("direct-hash");

    public List<(ArrKind Service, ArrRelease Release)> AddDirectCalls { get; } = [];

    public Task<string> AddDirectAsync(ArrKind service, ArrRelease release, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            AddDirectCalls.Add((service, release));
        }

        return AddDirect(service, release);
    }
}
