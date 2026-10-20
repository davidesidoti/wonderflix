using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RatingRoundServiceTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 20, 21, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly PartyDirectory _parties;
    private readonly RatingService _ratings;
    private readonly RatingRoundService _rounds;
    private readonly Guid _group = Guid.NewGuid();
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly UserRef _toad;
    private readonly RatedTitle _film;
    private readonly RatedTitle _season;
    private readonly Guid _last = Guid.NewGuid();
    private readonly Guid _middle = Guid.NewGuid();

    public RatingRoundServiceTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _toad = _server.AddUser("Toad");
        _server.AddSession("s-mario", _mario);
        _server.AddSession("s-luigi", _luigi);
        _server.AddSession("s-peach", _peach);
        _server.AddSession("s-toad", _toad);
        _server.Groups[_group] = ["mario", "LUIGI", "Peach"];
        _film = _server.AddRated("Il Padrino (1972)");
        _season = _server.AddRated("Breaking Bad · Stagione 2", isSeason: true);
        _server.RoundTargets[_film.Id] = _film.Id;
        _server.RoundTargets[_last] = _season.Id;
        _parties = new PartyDirectory(_time);
        _parties.Register(_group, _mario.Id, PartyModes.Friends);
        _ratings = TestRatings.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time));
        _rounds = TestRatings.Rounds(_server, _ratings, _time, _parties);
    }

    public void Dispose()
    {
        _rounds.Dispose();
        _folder.Dispose();
    }

    private static string N(Guid id) => id.ToString("N");

    private static OpenRatingRoundRequest Request(Guid group, Guid item) => new() { GroupId = N(group), ItemId = N(item) };

    private static RateRequest Vote(int score, string? comment = null) => new() { Score = score, Comment = comment };

    private static T Last<T>(IReadOnlyList<string> payloads) =>
        JsonSerializer.Deserialize<JsonElement>(payloads[^1]).GetProperty("State").Deserialize<T>()!;

    private static void AssertConflict(string reason, RatingOutcome outcome)
    {
        Assert.Equal(HubStatus.Conflict, outcome.Status);
        Assert.Equal(reason, outcome.Reason);
    }

    [Fact]
    public void OpeningTheSameTitleTwiceKeepsOneRoundAndAnotherTitleReplacesIt()
    {
        var first = _rounds.Open(_mario.Id, Request(_group, _film.Id)).State!;
        var again = _rounds.Open(_luigi.Id, Request(_group, _film.Id)).State!;
        Assert.Equal(first.EndsAt, again.EndsAt);
        Assert.Equal(N(_film.Id), again.ItemId);

        var season = _rounds.Open(_mario.Id, Request(_group, _last)).State!;
        Assert.Equal(N(_season.Id), season.ItemId);
        Assert.Equal(N(_season.Id), _rounds.Get(_peach.Id, _group).State!.ItemId);
    }

    [Fact]
    public void UpdatesWhileVotingNeverCarryOtherVotes()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        _rounds.Vote(_luigi.Id, _group, Vote(9, "Splendido"));
        _time.Advance(RatingRoundService.PushInterval);
        _rounds.Vote(_luigi.Id, _group, Vote(8, "Splendido, sì"));
        _time.Advance(RatingRoundService.PushInterval);

        Assert.All(_server.Sent.Where(s => s.SessionId != "s-luigi"), sent => Assert.DoesNotContain("Splendido", sent.Payload));
        var toMario = Last<RatingRoundDto>(_server.SentTo("s-mario"));
        Assert.True(toMario.CanReveal);
        Assert.False(Last<RatingRoundDto>(_server.SentTo("s-luigi")).CanReveal);
        Assert.Equal(new RatingScoreDto(8, "Splendido, sì"), Last<RatingRoundDto>(_server.SentTo("s-luigi")).Mine);
    }

    [Fact]
    public void TheTimerRevealsAfterTwoMinutesWithoutCalls()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        _time.Advance(RatingRoundService.VotingTime);
        Assert.Equal(RatingPhases.Revealed, Last<RatingRoundDto>(_server.SentTo("s-peach")).Phase);
    }

    [Fact]
    public void OpenNeedsAMovieOrTheLastEpisode()
    {
        Assert.Equal(HubStatus.Invalid, _rounds.Open(_mario.Id, Request(_group, _middle)).Status);
        Assert.Equal(HubStatus.Invalid, _rounds.Open(_mario.Id, new OpenRatingRoundRequest { GroupId = N(_group), ItemId = "x" }).Status);
        Assert.Equal(HubStatus.Invalid, _rounds.Open(_mario.Id, new OpenRatingRoundRequest { GroupId = "x", ItemId = N(_film.Id) }).Status);
        Assert.Equal(HubStatus.Invalid, _rounds.Open(_mario.Id, null).Status);

        _server.Unseen.Add((_mario.Id, _film.Id));
        Assert.Equal(HubStatus.Invalid, _rounds.Open(_mario.Id, Request(_group, _film.Id)).Status);
        _server.Unseen.Clear();

        // Un bersaglio che la scheda rifiuterebbe (non votabile) non apre nulla.
        var unrated = Guid.NewGuid();
        _server.RoundTargets[unrated] = unrated;
        Assert.Equal(HubStatus.Invalid, _rounds.Open(_mario.Id, Request(_group, unrated)).Status);

        _server.RatingLibraryFails = true;
        Assert.Equal(HubStatus.Invalid, _rounds.Open(_mario.Id, Request(_group, _film.Id)).Status);
    }

    [Fact]
    public void ATimerFailureIsLoggedAndDoesNotEscape()
    {
        var logger = new RecordingLogger<RatingRoundService>(throwOnReveal: true);
        using var rounds = new RatingRoundService(
            _ratings, _server, _server, _server, _server, _server, _parties, _server, _time, logger);
        rounds.Open(_mario.Id, Request(_group, _film.Id));

        _time.Advance(RatingRoundService.VotingTime);

        var warning = Assert.Single(logger.Entries, e => e.Level == Microsoft.Extensions.Logging.LogLevel.Warning);
        Assert.NotNull(warning.Exception);
        Assert.DoesNotContain("Mario", warning.Message);
    }

    [Fact]
    public void NonMembersGet409AndAnEmptyGet()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        AssertConflict(RatingReasons.NotMember, _rounds.Open(_toad.Id, Request(_group, _film.Id)));
        var get = _rounds.Get(_toad.Id, _group);
        Assert.Equal(HubStatus.Ok, get.Status);
        Assert.Null(get.State);
        AssertConflict(RatingReasons.NotMember, _rounds.Vote(_toad.Id, _group, Vote(5)));

        var unknown = Guid.NewGuid();
        AssertConflict(RatingReasons.NotMember, _rounds.Open(_mario.Id, Request(unknown, _film.Id)));
        AssertConflict(RatingReasons.Closed, _rounds.Skip(_mario.Id, unknown));
    }

    [Fact]
    public void ParticipantsMatchUsersIgnoringCase()
    {
        var state = _rounds.Open(_mario.Id, Request(_group, _film.Id)).State!;
        Assert.Contains(state.Voters, v => v.Name == "Luigi");
        Assert.Equal(HubStatus.Ok, _rounds.Vote(_luigi.Id, _group, Vote(5)).Status);
    }

    [Fact]
    public void RevealsWhenEveryoneVotedOrSkipped()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        _rounds.Vote(_mario.Id, _group, Vote(7));
        _rounds.Vote(_luigi.Id, _group, Vote(9));
        var state = _rounds.Skip(_peach.Id, _group).State!;

        Assert.Equal(RatingPhases.Revealed, state.Phase);
        Assert.Equal(new[] { "Luigi", "Mario" }, state.Results!.Select(r => r.Name));
        Assert.Equal(8.0, state.Average);
    }

    [Fact]
    public void TheCreatorRevealsAndOthersCannot()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        AssertConflict(RatingReasons.NotCreator, _rounds.Reveal(_luigi.Id, _group));
        var revealed = _rounds.Reveal(_mario.Id, _group).State!;
        Assert.Equal(RatingPhases.Revealed, revealed.Phase);
        var again = _rounds.Reveal(_mario.Id, _group);
        Assert.Equal(HubStatus.Ok, again.Status);
        Assert.Equal(revealed.Rev, again.State!.Rev);
    }

    [Fact]
    public void AnUnknownCreatorLeavesOnlyAllVotedAndTimeout()
    {
        using var rounds = TestRatings.Rounds(_server, _ratings, _time);
        var state = rounds.Open(_mario.Id, Request(_group, _film.Id)).State!;
        Assert.False(state.CanReveal);
        AssertConflict(RatingReasons.NotCreator, rounds.Reveal(_mario.Id, _group));
    }

    [Fact]
    public void LeaversAreNotAwaitedAndJoinersWait()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        _rounds.Vote(_mario.Id, _group, Vote(7));
        _rounds.Vote(_luigi.Id, _group, Vote(9));
        _server.Groups[_group].Remove("Peach");
        Assert.Equal(RatingPhases.Revealed, _rounds.Get(_mario.Id, _group).State!.Phase);

        _rounds.Open(_mario.Id, Request(_group, _last));
        _server.Groups[_group].Add("Toad");
        var voters = _rounds.Get(_mario.Id, _group).State!.Voters;
        Assert.Equal(RatingVoterStatuses.Waiting, voters.Single(v => v.Name == "Toad").Status);
    }

    [Fact]
    public void AVoteAfterRevealIsSavedAndShown()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        _time.Advance(RatingRoundService.VotingTime);

        var state = _rounds.Vote(_peach.Id, _group, Vote(6)).State!;
        Assert.Contains(state.Results!, r => r.Name == "Peach" && r.Score == 6);
        Assert.Equal(new RatingScoreDto(6, null), _ratings.ForItem(_peach.Id, N(_film.Id)).Value!.Mine);
        AssertConflict(RatingReasons.Closed, _rounds.Skip(_peach.Id, _group));
    }

    [Fact]
    public void AVoteDoesNotNeedTheTitleWatchedAndInvalidVotesAre400()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        var before = _rounds.Get(_mario.Id, _group).State!;
        Assert.Equal(HubStatus.Invalid, _rounds.Vote(_mario.Id, _group, Vote(11)).Status);
        var after = _rounds.Get(_mario.Id, _group).State!;
        Assert.Equal(before.Rev, after.Rev);
        Assert.Null(after.Mine);

        Assert.Empty(_server.WatchedTitles);
        Assert.Equal(HubStatus.Ok, _rounds.Vote(_mario.Id, _group, Vote(10)).Status);
    }

    [Fact]
    public void RoundsAreDiscardedTenMinutesAfterRevealOrWhenTheGroupEnds()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        _rounds.Vote(_mario.Id, _group, Vote(7));
        _rounds.Vote(_luigi.Id, _group, Vote(9));
        _rounds.Skip(_peach.Id, _group);

        _time.Advance(RatingRoundService.RevealedKept - TimeSpan.FromSeconds(1));
        _rounds.Cleanup();
        Assert.NotNull(_rounds.Get(_mario.Id, _group).State);
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(_rounds.Cleanup() > 0);
        Assert.Null(_rounds.Get(_mario.Id, _group).State);

        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        var names = _server.Groups[_group];
        _server.Groups.Remove(_group);
        Assert.True(_rounds.Cleanup() > 0);
        _server.Groups[_group] = names;
        Assert.Null(_rounds.Get(_mario.Id, _group).State);
    }

    [Fact]
    public void UpdatesAreCoalescedEvery250ms()
    {
        _rounds.Open(_mario.Id, Request(_group, _film.Id));
        _time.Advance(RatingRoundService.PushInterval);
        _server.Sent.Clear();

        _rounds.Vote(_mario.Id, _group, Vote(7));
        _rounds.Vote(_mario.Id, _group, Vote(8));
        _rounds.Vote(_luigi.Id, _group, Vote(9));
        Assert.Single(_server.SentTo("s-peach"));
        var firstRev = Last<RatingRoundDto>(_server.SentTo("s-peach")).Rev;

        _time.Advance(RatingRoundService.PushInterval);
        Assert.Equal(2, _server.SentTo("s-peach").Count);
        Assert.True(Last<RatingRoundDto>(_server.SentTo("s-peach")).Rev > firstRev);
    }
}
