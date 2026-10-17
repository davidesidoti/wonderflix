using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class MatchStackBuilderTests
{
    private static readonly MatchFilters AnyTitle = new(true, true, null, null);

    private readonly FakeServer _server = new();
    private readonly UserRef _mario;
    private readonly UserRef _luigi;

    public MatchStackBuilderTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
    }

    private MatchStackBuilder Builder() =>
        new(_server, _server, _server, NullLogger<MatchStackBuilder>.Instance);

    private Guid Movie(TimeSpan? runtime = null)
    {
        var candidate = new MatchCandidate(Guid.NewGuid(), true, runtime?.Ticks);
        _server.MatchCandidates.Add(candidate);
        return candidate.Id;
    }

    private Guid Rated(float? rating)
    {
        var candidate = new MatchCandidate(Guid.NewGuid(), true, null, rating);
        _server.MatchCandidates.Add(candidate);
        return candidate.Id;
    }

    private Guid Series()
    {
        var candidate = new MatchCandidate(Guid.NewGuid(), false, null);
        _server.MatchCandidates.Add(candidate);
        return candidate.Id;
    }

    private IReadOnlyList<Guid> Draw(MatchFilters? filters = null, IReadOnlyCollection<Guid>? exclude = null) =>
        Builder().Draw(_mario.Id, [_mario.Id, _luigi.Id], filters ?? AnyTitle, exclude ?? []);

    [Fact]
    public void TheQueryIsOnTheCreatorsLibrary()
    {
        var shown = new[] { Guid.NewGuid() };
        var filters = new MatchFilters(true, false, null, "Horror");
        Draw(filters, shown);

        var query = Assert.Single(_server.MatchQueries);
        Assert.Equal(_mario.Id, query.UserId);
        Assert.Equal(filters, query.Filters);
        Assert.Equal(shown, query.Exclude);
        Assert.Equal(MatchStackBuilder.CandidateLimit, query.Limit);
    }

    [Fact]
    public void OnlyTitlesEveryMemberCanSeeAndNeverWatched()
    {
        var hidden = Movie();
        var seenByLuigi = Movie();
        var startedByMario = Series();
        var good = Movie();
        _server.Unseen.Add((_luigi.Id, hidden));
        _server.Watched[(_luigi.Id, seenByLuigi)] = DateTimeOffset.UnixEpoch;
        _server.Watched[(_mario.Id, startedByMario)] = DateTimeOffset.UnixEpoch;

        Assert.Equal(new[] { good }, Draw());
    }

    [Fact]
    public void TheTypeIsCheckedAgain()
    {
        var movie = Movie();
        var series = Series();

        Assert.Equal(new[] { movie }, Draw(new MatchFilters(true, false, null, null)));
        Assert.Equal(new[] { series }, Draw(new MatchFilters(false, true, null, null)));
        Assert.Equal(new[] { movie, series }, Draw());
    }

    [Fact]
    public void TheDurationLimitsOnlyMoviesAndNeedsAKnownRuntime()
    {
        var short1 = Movie(TimeSpan.FromMinutes(89));
        Movie(TimeSpan.FromMinutes(90));
        Movie();
        var series = Series();

        Assert.Equal(new[] { short1, series }, Draw(new MatchFilters(true, true, TimeSpan.FromMinutes(90), null)));
    }

    [Fact]
    public void TheRatingNeedsAKnownScoreInTheRange()
    {
        var good = Rated(7f);
        Rated(6.9f);
        var bad = Rated(5f);
        Rated(null);

        Assert.Equal(new[] { good }, Draw(new MatchFilters(true, true, null, null, MinRating: 7)));
        Assert.Equal(new[] { bad }, Draw(new MatchFilters(true, true, null, null, MaxRating: 5)));
        Assert.Equal(4, Draw().Count);
    }

    [Fact]
    public void ExcludedAndRepeatedTitlesAreSkipped()
    {
        var old = Movie();
        var fresh = Movie();
        _server.MatchCandidates.Add(new MatchCandidate(fresh, true, null));

        // La finta li toglie già; il costruttore li ricontrolla comunque.
        Assert.Equal(new[] { fresh }, Builder().Draw(_mario.Id, [_mario.Id], AnyTitle, new HashSet<Guid> { old }));
        Assert.Equal(new[] { old, fresh }, Draw());
    }

    [Fact]
    public void TheStackStopsAtThirty()
    {
        for (var i = 0; i < MatchStackBuilder.StackSize + 5; i++)
        {
            Movie();
        }

        Assert.Equal(MatchStackBuilder.StackSize, Draw().Count);
    }

    [Fact]
    public void ChecksStopAtTheFirstMemberThatFails()
    {
        var hidden = Movie();
        _server.Unseen.Add((_mario.Id, hidden));

        Draw();

        Assert.DoesNotContain(_server.SeenChecks, check => check.UserId == _luigi.Id);
    }

    [Fact]
    public void LibraryErrorsGiveAShorterOrEmptyStack()
    {
        Movie();
        _server.MatchLibraryFails = true;
        Assert.Empty(Draw());

        _server.MatchLibraryFails = false;
        _server.LibraryFails = true;
        Assert.Empty(Draw());
    }
}
