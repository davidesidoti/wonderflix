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
    public async Task AMissingTitleIsRememberedForAFewMinutes()
    {
        var cache = new SeerrTitleCache(_seerr, _time);

        Assert.Null(await cache.GetAsync("movie", 1, "it", Ct));

        // Apparso su Seerr dopo: finché la mancanza è in memoria resta null.
        _seerr.Movies[1] = new SeerrMovie { Title = "Uno" };
        Assert.Null(await cache.GetAsync("movie", 1, "it", Ct));

        _time.Advance(SeerrTitleCache.MissCacheFor);
        Assert.Equal("Uno", (await cache.GetAsync("movie", 1, "it", Ct))!.Title);
    }

    [Fact]
    public async Task AMissingTitleIsLookedUpOnceInFiveMinutesAndAgainAfter()
    {
        var cache = new SeerrTitleCache(_seerr, _time);

        await cache.GetAsync("movie", 1, "it", Ct);
        _time.Advance(SeerrTitleCache.MissCacheFor - TimeSpan.FromSeconds(1));
        await cache.GetAsync("movie", 1, "it", Ct);
        Assert.Single(_seerr.Calls, "GetMovie");

        _time.Advance(TimeSpan.FromSeconds(1));
        await cache.GetAsync("movie", 1, "it", Ct);
        Assert.Equal(2, _seerr.Calls.Count(c => c == "GetMovie"));
    }

    [Theory]
    [InlineData(SeerrError.Unavailable)]
    [InlineData(SeerrError.Auth)]
    [InlineData(SeerrError.NotConfigured)]
    public async Task AnErrorThatIsNotAMissingTitleIsNotRemembered(SeerrError error)
    {
        var cache = new SeerrTitleCache(_seerr, _time);

        // Seerr in difficoltà non vuol dire che il titolo manca: niente memoria.
        _seerr.FailWith = error;
        Assert.Null(await cache.GetAsync("movie", 1, "it", Ct));

        _seerr.FailWith = null;
        _seerr.Movies[1] = new SeerrMovie { Title = "Uno" };
        Assert.Equal("Uno", (await cache.GetAsync("movie", 1, "it", Ct))!.Title);
        Assert.Equal(2, _seerr.Calls.Count(c => c == "GetMovie"));
    }

    [Fact]
    public async Task OnlyAFewLookupsRunAtTheSameTime()
    {
        const int Titles = 10;
        for (var id = 1; id <= Titles; id++)
        {
            _seerr.Movies[id] = new SeerrMovie { Title = $"Film {id}" };
        }

        var gate = new TaskCompletionSource();
        _seerr.TitlesGate = gate.Task;
        var cache = new SeerrTitleCache(_seerr, _time);

        var lookups = Enumerable.Range(1, Titles).Select(id => cache.GetAsync("movie", id, "it", Ct)).ToList();
        await Task.Delay(50);

        // Il limite regge davvero: le prime chiamate sono in corso e le altre aspettano.
        Assert.Equal(SeerrTitleCache.MaxParallelLookups, _seerr.InFlightTitles);
        gate.SetResult();
        var results = await Task.WhenAll(lookups);

        Assert.True(_seerr.MaxInFlightTitles <= SeerrTitleCache.MaxParallelLookups);
        Assert.All(results, title => Assert.NotNull(title));
        Assert.Equal(Titles, _seerr.Calls.Count(c => c == "GetMovie"));
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
