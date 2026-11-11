using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class TrailerResolverTests
{
    private static readonly Guid User = Guid.NewGuid();
    private static readonly Guid Item = Guid.NewGuid();

    private readonly FakeTrailerLibrary _library = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeSeerrSettings _settings = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero));

    private TrailerResolver Resolver() => new(_library, _seerr, _settings, _time);

    private static SeerrVideo Video(string id, string type = "Trailer") =>
        new() { Site = "YouTube", Type = type, Url = "https://www.youtube.com/watch?v=" + id };

    private void MovieWithTrailer(int tmdbId, string videoId) =>
        _seerr.Movies[tmdbId] = new SeerrMovie { Id = tmdbId, RelatedVideos = [Video(videoId)] };

    [Fact]
    public async Task JellyfinTrailerComesFirst()
    {
        _library.Item = new TrailerItem("movie", 1, ["https://www.youtube.com/watch?v=AmsN8z7tl48"]);

        var result = await Resolver().ResolveAsync(User, new TrailerSubject(Item, null, null), default);

        Assert.Equal("AmsN8z7tl48", result?.VideoId);
        Assert.Empty(_seerr.Calls);
    }

    [Fact]
    public async Task SeerrFillsTheGap()
    {
        _library.Item = new TrailerItem("movie", 1375646, []);
        MovieWithTrailer(1375646, "25WcssMq1VM");

        var result = await Resolver().ResolveAsync(User, new TrailerSubject(Item, null, null), default);

        Assert.Equal("25WcssMq1VM", result?.VideoId);
        Assert.Equal(["GetMovie"], _seerr.Calls);
    }

    [Fact]
    public async Task TmdbSubjectGoesStraightToSeerr()
    {
        _seerr.Shows[42] = new SeerrTv { Id = 42, RelatedVideos = [Video("dQw4w9WgXcQ")] };

        var result = await Resolver().ResolveAsync(User, new TrailerSubject(null, "tv", 42), default);

        Assert.Equal("dQw4w9WgXcQ", result?.VideoId);
        Assert.Equal(["GetTv"], _seerr.Calls);
    }

    [Fact]
    public async Task NothingWhenSeerrIsNotConfigured()
    {
        _settings.Url = "";
        _settings.ApiKey = "";
        _library.Item = new TrailerItem("movie", 1, []);

        Assert.Null(await Resolver().ResolveAsync(User, new TrailerSubject(Item, null, null), default));
        Assert.Empty(_seerr.Calls);
    }

    [Fact]
    public async Task NothingForAnItemTheUserCannotSee()
    {
        _library.Item = null;
        MovieWithTrailer(1, "25WcssMq1VM");

        Assert.Null(await Resolver().ResolveAsync(User, new TrailerSubject(Item, "movie", 1), default));
        Assert.Empty(_seerr.Calls);
    }

    [Fact]
    public async Task AnswersAreRememberedForADay()
    {
        MovieWithTrailer(1, "25WcssMq1VM");
        var resolver = Resolver();
        var subject = new TrailerSubject(null, "movie", 1);

        await resolver.ResolveAsync(User, subject, default);
        await resolver.ResolveAsync(User, subject, default);
        Assert.Single(_seerr.Calls);

        _time.Advance(TimeSpan.FromHours(24) + TimeSpan.FromSeconds(1));
        await resolver.ResolveAsync(User, subject, default);
        Assert.Equal(2, _seerr.Calls.Count);
    }

    [Fact]
    public async Task NoTrailerIsRemembered()
    {
        var resolver = Resolver();
        var subject = new TrailerSubject(null, "movie", 7);

        Assert.Null(await resolver.ResolveAsync(User, subject, default));
        Assert.Null(await resolver.ResolveAsync(User, subject, default));
        Assert.Single(_seerr.Calls);
    }

    [Fact]
    public async Task SeerrErrorsAreNotRemembered()
    {
        MovieWithTrailer(1, "25WcssMq1VM");
        _seerr.FailWith = SeerrError.Unavailable;
        var resolver = Resolver();
        var subject = new TrailerSubject(null, "movie", 1);

        Assert.Null(await resolver.ResolveAsync(User, subject, default));
        _seerr.FailWith = null;
        Assert.Equal("25WcssMq1VM", (await resolver.ResolveAsync(User, subject, default))?.VideoId);
        Assert.Equal(2, _seerr.Calls.Count);
    }

    [Fact]
    public async Task WasResolvedOnlyForReturnedIds()
    {
        MovieWithTrailer(1, "25WcssMq1VM");
        var resolver = Resolver();

        await resolver.ResolveAsync(User, new TrailerSubject(null, "movie", 1), default);

        Assert.True(resolver.WasResolved("25WcssMq1VM"));
        Assert.False(resolver.WasResolved("dQw4w9WgXcQ"));
    }

    [Theory]
    [InlineData("https://www.youtube.com/watch?v=AmsN8z7tl48", "AmsN8z7tl48")]
    [InlineData("https://youtu.be/AmsN8z7tl48", "AmsN8z7tl48")]
    [InlineData("https://www.youtube.com/embed/AmsN8z7tl48", "AmsN8z7tl48")]
    [InlineData("https://www.youtube-nocookie.com/embed/AmsN8z7tl48", "AmsN8z7tl48")]
    [InlineData("https://m.youtube.com/watch?v=AmsN8z7tl48&t=3", "AmsN8z7tl48")]
    [InlineData("https://vimeo.com/1", null)]
    [InlineData("javascript:x", null)]
    [InlineData(null, null)]
    [InlineData("https://www.youtube.com/watch?v=AmsN8z7tl4", null)]
    public void YouTubeIdParsesTheKnownShapes(string? url, string? expected) =>
        Assert.Equal(expected, YouTubeId.FromUrl(url));
}
