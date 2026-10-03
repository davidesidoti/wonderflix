using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class NewTitlesWaveTests
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 4, 20, 0, 0, TimeSpan.Zero);

    private static LibraryTitle Title(bool isMovie, params string[] keys) =>
        new(Guid.NewGuid(), isMovie, "x", null, Guid.Empty, string.Empty, string.Empty, null, null, keys, true);

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
}
