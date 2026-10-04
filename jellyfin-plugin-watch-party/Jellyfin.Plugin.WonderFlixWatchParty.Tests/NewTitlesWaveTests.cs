using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class NewTitlesWaveTests
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 4, 20, 0, 0, TimeSpan.Zero);

    private static LibraryTitle Title(bool isMovie, params string[] keys) =>
        new(Guid.NewGuid(), isMovie, "x", null, Guid.Empty, string.Empty, string.Empty, null, null, keys, true);

    private static LibraryTitle Episode(string seriesKey, int? season) =>
        new(Guid.NewGuid(), false, "x", null, Guid.NewGuid(), "Serie", seriesKey, season, 1, [], true);

    [Fact]
    public void QuietCountsFromTheLastChangeOverdueFromTheStart()
    {
        var wave = new NewTitlesWave(T0);
        wave.Add(Guid.NewGuid(), T0.AddMinutes(10));

        Assert.False(wave.IsQuiet(T0.AddMinutes(24), TimeSpan.FromMinutes(15)));
        Assert.True(wave.IsQuiet(T0.AddMinutes(25), TimeSpan.FromMinutes(15)));
        Assert.False(wave.IsOverdue(T0.AddMinutes(119), TimeSpan.FromHours(2)));
        Assert.True(wave.IsOverdue(T0.AddHours(2), TimeSpan.FromHours(2)));
    }

    [Fact]
    public void ARemovedTitleLeavesTheWaveAndMarksReplacementsOfTheSameKind()
    {
        var wave = new NewTitlesWave(T0);
        var id = Guid.NewGuid();
        wave.Add(id, T0);

        wave.Remove(id, isMovie: true, ["Tmdb:1"], T0.AddMinutes(1));

        Assert.Equal(0, wave.Count);
        Assert.Empty(wave.AddedIds);
        Assert.Equal(T0.AddMinutes(1), wave.LastChangeAt);
        Assert.True(wave.IsReplacement(Title(true, "tmdb:1")));
        Assert.False(wave.IsReplacement(Title(false, "Tmdb:1")));
        Assert.False(wave.IsReplacement(Title(true, "Tmdb:2")));
        Assert.False(wave.IsReplacement(Title(true)));
    }

    [Fact]
    public void AnOlderWaveAbsorbsANewerOne()
    {
        var older = new NewTitlesWave(T0);
        var kept = Guid.NewGuid();
        var removedLater = Guid.NewGuid();
        var back = Guid.NewGuid();
        older.Add(kept, T0);
        older.Add(removedLater, T0.AddMinutes(1));
        older.Add(back, T0.AddMinutes(2));
        older.RecordFailedClose();
        var newer = new NewTitlesWave(T0.AddMinutes(20));
        var added = Guid.NewGuid();
        newer.Add(added, T0.AddMinutes(20));
        newer.Remove(removedLater, isMovie: true, ["Tmdb:7"], T0.AddMinutes(21));
        // Tolto e rimesso nella nuova: resta.
        newer.Remove(back, isMovie: true, [], T0.AddMinutes(22));
        newer.Add(back, T0.AddMinutes(23));

        older.Absorb(newer);

        Assert.Equal(new[] { kept, back, added }.OrderBy(id => id), older.AddedIds.OrderBy(id => id));
        Assert.Equal(T0, older.StartedAt);
        Assert.Equal(T0.AddMinutes(23), older.LastChangeAt);
        Assert.True(older.IsReplacement(Title(true, "Tmdb:7")));
        Assert.True(older.IsOverdue(T0.AddHours(2), TimeSpan.FromHours(2)));
        Assert.Equal(2, older.RecordFailedClose());
    }

    [Fact]
    public void EpisodesOfARemovedSeriesOrSeasonFolderAreReplacements()
    {
        var wave = new NewTitlesWave(T0);

        // Una serie intera (stagione null) e una stagione; la chiave vuota non conta.
        wave.RemoveSeries("bear-key", season: null, T0.AddMinutes(1));
        wave.RemoveSeries("lost-key", season: 2, T0.AddMinutes(2));
        wave.RemoveSeries(string.Empty, season: null, T0.AddMinutes(3));

        Assert.Equal(0, wave.Count);
        Assert.Equal(T0.AddMinutes(3), wave.LastChangeAt);
        Assert.True(wave.IsReplacement(Episode("bear-key", 1)));
        Assert.True(wave.IsReplacement(Episode("bear-key", null)));
        Assert.True(wave.IsReplacement(Episode("lost-key", 2)));
        Assert.False(wave.IsReplacement(Episode("lost-key", 1)));
        Assert.False(wave.IsReplacement(Episode("lost-key", null)));
        Assert.False(wave.IsReplacement(Episode("Bear-Key", 1)));
        Assert.False(wave.IsReplacement(Episode(string.Empty, 1)));
        Assert.False(wave.IsReplacement(Title(true)));

        var older = new NewTitlesWave(T0);
        older.Absorb(wave);
        Assert.True(older.IsReplacement(Episode("bear-key", 3)));
        Assert.True(older.IsReplacement(Episode("lost-key", 2)));
        Assert.False(older.IsReplacement(Episode("lost-key", 1)));
    }
}
