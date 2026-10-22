using Xunit;
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class RatingRoundTests
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 20, 21, 0, 0, TimeSpan.Zero);
    private readonly UserRef _mario = new(Guid.NewGuid(), "Mario", true, true);
    private readonly UserRef _luigi = new(Guid.NewGuid(), "Luigi", true, true);
    private readonly UserRef _peach = new(Guid.NewGuid(), "Peach", true, true);

    private static string N(Guid id) => id.ToString("N");

    private static RatingRound Round(params UserRef[] present)
    {
        var round = new RatingRound(Guid.NewGuid(), Guid.NewGuid(), T0, TimeSpan.FromMinutes(2));
        round.SetPresent(present);
        return round;
    }

    private static Dictionary<Guid, StoredRating> Ratings(params (Guid UserId, int Score, string? Comment)[] items) =>
        items.ToDictionary(i => i.UserId, i => new StoredRating(i.UserId, i.Score, i.Comment, T0, T0));

    [Fact]
    public void WhileVotingTheSnapshotHasOnlyStatuses()
    {
        var round = Round(_mario, _luigi);
        round.Vote(_luigi.Id);
        var ratings = Ratings((_luigi.Id, 9, "Bello"), (_mario.Id, 7, null));

        var seen = round.Snapshot(_mario.Id, viewerIsCreator: true, ratings);
        Assert.Equal(RatingPhases.Voting, seen.Phase);
        Assert.True(seen.CanReveal);
        Assert.Equal(new RatingScoreDto(7, null), seen.Mine);
        Assert.Equal(
            new[] { new RatingVoterDto(N(_luigi.Id), "Luigi", RatingVoterStatuses.Voted), new RatingVoterDto(N(_mario.Id), "Mario", RatingVoterStatuses.Waiting) },
            seen.Voters);
        Assert.Null(seen.Results);
        Assert.Null(seen.Average);
        Assert.DoesNotContain("Bello", JsonSerializer.Serialize(seen));
    }

    [Fact]
    public void RevealedResultsAreThePresentVotersFromTheHighest()
    {
        var round = Round(_mario, _luigi, _peach);
        round.Vote(_mario.Id);
        round.Vote(_luigi.Id);
        round.Skip(_peach.Id);
        Assert.Equal("allVoted", round.RevealIfDue(T0));
        var seen = round.Snapshot(_luigi.Id, viewerIsCreator: false, Ratings((_mario.Id, 7, null), (_luigi.Id, 9, "Bello")));
        Assert.Equal(new[] { "Luigi", "Mario" }, seen.Results!.Select(r => r.Name));
        Assert.Equal(new RatingResultDto(N(_luigi.Id), "Luigi", 9, "Bello"), seen.Results![0]);
        Assert.Equal(8.0, seen.Average);
        Assert.False(seen.CanReveal);
    }

    [Fact]
    public void LeaversAreNotAwaitedAndJoinersWait()
    {
        var round = Round(_mario, _luigi);
        round.Vote(_mario.Id);
        Assert.Null(round.RevealIfDue(T0));
        round.SetPresent([_mario]);
        Assert.Equal("allVoted", round.RevealIfDue(T0));

        var other = Round(_mario);
        other.Vote(_mario.Id);
        other.SetPresent([_mario, _peach]);
        Assert.Equal(RatingVoterStatuses.Waiting, other.Snapshot(_mario.Id, false, Ratings()).Voters.Single(v => v.Name == "Peach").Status);
        Assert.Null(other.RevealIfDue(T0));
    }

    [Fact]
    public void ALeaverWhoVotedIsNotInTheResults()
    {
        var round = Round(_mario, _luigi);
        round.Vote(_mario.Id);
        round.Vote(_luigi.Id);
        round.SetPresent([_mario]);
        round.Reveal(T0);
        var seen = round.Snapshot(_mario.Id, false, Ratings((_mario.Id, 7, null), (_luigi.Id, 9, null)));
        Assert.Equal(new[] { "Mario" }, seen.Results!.Select(r => r.Name));
        Assert.Equal(7.0, seen.Average);
    }

    [Fact]
    public void TheDeadlineRevealsAfterTwoMinutes()
    {
        var round = Round(_mario, _luigi);
        Assert.Null(round.RevealIfDue(T0 + new TimeSpan(0, 1, 59)));
        Assert.Equal("timeout", round.RevealIfDue(T0 + TimeSpan.FromMinutes(2)));
        Assert.Equal(T0 + TimeSpan.FromMinutes(2), round.RevealedAt);
        Assert.Equal(RatingPhases.Revealed, round.Phase);
    }

    [Fact]
    public void SkipOnlyWhileVotingAndVoteAlsoAfter()
    {
        var round = Round(_mario, _luigi);
        round.Reveal(T0);
        Assert.False(round.Skip(_mario.Id));
        round.Vote(_luigi.Id);
        var seen = round.Snapshot(_mario.Id, false, Ratings((_luigi.Id, 6, null)));
        Assert.Equal(RatingVoterStatuses.Voted, seen.Voters.Single(v => v.Name == "Luigi").Status);
        Assert.Equal(new[] { "Luigi" }, seen.Results!.Select(r => r.Name));
    }

    [Fact]
    public void RevGrowsOnlyWithAVisibleChange()
    {
        var round = Round(_mario, _luigi);
        var rev = round.Rev;
        round.SetPresent([_mario, _luigi]);
        Assert.Equal(rev, round.Rev);
        round.Vote(_mario.Id);
        Assert.Equal(rev + 1, round.Rev);
        round.Vote(_mario.Id);
        Assert.Equal(rev + 2, round.Rev);
        round.Skip(_luigi.Id);
        Assert.Equal(rev + 3, round.Rev);
        round.SetPresent([_mario, _peach]);
        Assert.Equal(rev + 4, round.Rev);
        round.Reveal(T0);
        Assert.Equal(rev + 5, round.Rev);
        round.Reveal(T0);
        Assert.Equal(rev + 5, round.Rev);
    }
}
