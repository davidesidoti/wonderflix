using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrTitleCacheTests
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTimeProvider _time = new();

    [Fact]
    public async Task TitlesComeFromSeerrOnceAnHourPerLanguage()
    {
        _seerr.Movies[438631] = new SeerrMovie { Title = "Dune", ReleaseDate = "2021-09-15", PosterPath = "/a.jpg" };
        _seerr.Shows[90228] = new SeerrTv { Name = "Dune: Prophecy", FirstAirDate = "2024-11-17" };
        var cache = new SeerrTitleCache(_seerr, _time);

        Assert.Equal(new SeerrTitle("Dune", 2021, "/a.jpg"), await cache.GetAsync("movie", 438631, "it", Ct));
        Assert.Equal(new SeerrTitle("Dune: Prophecy", 2024, null), await cache.GetAsync("tv", 90228, "it", Ct));
        await cache.GetAsync("movie", 438631, "it", Ct);
        Assert.Single(_seerr.Calls, "GetMovie");

        await cache.GetAsync("movie", 438631, "en", Ct);
        Assert.Equal(2, _seerr.Calls.Count(c => c == "GetMovie"));

        _time.Advance(SeerrTitleCache.CacheFor);
        await cache.GetAsync("movie", 438631, "it", Ct);
        Assert.Equal(3, _seerr.Calls.Count(c => c == "GetMovie"));
    }

    [Fact]
    public async Task AMissingTitleIsNullAndNotRemembered()
    {
        var cache = new SeerrTitleCache(_seerr, _time);

        Assert.Null(await cache.GetAsync("movie", 1, "it", Ct));

        _seerr.Movies[1] = new SeerrMovie { Title = "Uno" };
        Assert.Equal("Uno", (await cache.GetAsync("movie", 1, "it", Ct))!.Title);
    }

    [Fact]
    public async Task PutWarmsTheCache()
    {
        var cache = new SeerrTitleCache(_seerr, _time);
        cache.Put("tv", 5, "it", new SeerrTitle("Cinque", null, null));

        Assert.Equal("Cinque", (await cache.GetAsync("tv", 5, "it", Ct))!.Title);
        Assert.Empty(_seerr.Calls);
    }
}
