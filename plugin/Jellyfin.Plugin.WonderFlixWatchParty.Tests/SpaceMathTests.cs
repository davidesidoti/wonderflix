using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SpaceMathTests
{
    private const long Gb = 1_000_000_000;

    private static readonly SeedSettings Settings = new(["itatorrents.xyz"], 10.0, 30);

    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-10-30T12:00:00Z");

    private static readonly HashSet<FileId> NoLibrary = [];

    private static readonly HashSet<FileId> TwoEpisodes = [Id(1), Id(2)];

    private static FileId Id(long inode) => new(1, inode);

    private static FileFact Fact(long inode, int links, long size = 5 * Gb) => new($"/media/{inode}.mkv", Id(inode), links, size);

    private static TorrentFacts Torrent(string hash, string host = "tracker.example.org", double ratio = 0, long seeding = 0) =>
        new(hash, hash, host, 5 * Gb, 1, ratio, seeding);

    private static TorrentIndex Index(IReadOnlyList<TorrentFacts> torrents, params (string Hash, string Path, long Inode)[] files) =>
        new(torrents, files.GroupBy(f => f.Hash).ToDictionary(
            g => g.Key,
            g => (IReadOnlyList<TorrentFile>)g.Select(f => new TorrentFile(f.Path, Id(f.Inode))).ToList()));

    private static TorrentIndex Pack() =>
        Index([Torrent("pack")], ("pack", "/dl/e1.mkv", 1), ("pack", "/dl/e2.mkv", 2));

    [Fact]
    public void AFileWithoutTorrentsIsFreedNow()
    {
        var result = SpaceMath.Estimate([Fact(1, 1)], Index([]), NoLibrary, Settings, Now);

        Assert.Equal(5 * Gb, result.FreeNowBytes);
        Assert.Empty(result.RemoveNow);
    }

    [Fact]
    public void AnUnprotectedTorrentIsRemovedWithTheTitle()
    {
        var index = Index([Torrent("a")], ("a", "/dl/1.mkv", 1));

        var result = SpaceMath.Estimate([Fact(1, 2)], index, new HashSet<FileId> { Id(1) }, Settings, Now);

        Assert.Equal(5 * Gb, result.FreeNowBytes);
        Assert.Equal(["a"], result.RemoveNow);
    }

    [Fact]
    public void AProtectedTorrentFreesLater()
    {
        var index = Index([Torrent("a", "itatorrents.xyz", 1, 5 * 86_400)], ("a", "/dl/1.mkv", 1));

        var result = SpaceMath.Estimate([Fact(1, 2)], index, new HashSet<FileId> { Id(1) }, Settings, Now);

        Assert.Equal(0, result.FreeNowBytes);
        Assert.Equal(5 * Gb, result.FreeLaterBytes);
        Assert.Equal(DateTimeOffset.Parse("2026-11-24T12:00:00Z"), result.FreeLaterAt);
        Assert.Equal(["a"], result.RemoveLater);
    }

    [Fact]
    public void ADownloadingTorrentFreesLaterWithoutDate()
    {
        var downloading = Torrent("a") with { Progress = 0.5 };
        var index = Index([downloading], ("a", "/dl/1.mkv", 1));

        var result = SpaceMath.Estimate([Fact(1, 2)], index, NoLibrary, Settings, Now);

        Assert.Equal(5 * Gb, result.FreeLaterBytes);
        Assert.Null(result.FreeLaterAt);
    }

    [Fact]
    public void APackWithOtherLibraryFilesIsKept()
    {
        var result = SpaceMath.Estimate([Fact(1, 2, 3 * Gb)], Pack(), TwoEpisodes, Settings, Now);

        Assert.Equal(3 * Gb, result.InPackBytes);
        Assert.Equal(0, result.FreeNowBytes);
        Assert.Empty(result.RemoveNow);
    }

    [Fact]
    public void AWholeSeasonPackGoesWithTheSeason()
    {
        var result = SpaceMath.Estimate([Fact(1, 2, 3 * Gb), Fact(2, 2, 4 * Gb)], Pack(), TwoEpisodes, Settings, Now);

        Assert.Equal(7 * Gb, result.FreeNowBytes);
        Assert.Equal(0, result.InPackBytes);
        Assert.Equal(["pack"], result.RemoveNow);
    }

    [Fact]
    public void AnUnknownExtraLinkKeepsTheBytes()
    {
        var index = Index([Torrent("a")], ("a", "/dl/1.mkv", 1));

        var result = SpaceMath.Estimate([Fact(1, 3)], index, new HashSet<FileId> { Id(1) }, Settings, Now);

        Assert.Equal(5 * Gb, result.InPackBytes);
        Assert.Equal(0, result.FreeNowBytes);
    }

    [Fact]
    public void CrossSeedSharesOnePath()
    {
        var index = Index([Torrent("a"), Torrent("b")], ("a", "/dl/1.mkv", 1), ("b", "/dl/1.mkv", 1));

        var result = SpaceMath.Estimate([Fact(1, 2)], index, new HashSet<FileId> { Id(1) }, Settings, Now);

        Assert.Equal(5 * Gb, result.FreeNowBytes);
        Assert.Equal(["a", "b"], result.RemoveNow);
    }

    [Fact]
    public void ASharedPathWithAKeptTorrentKeepsBoth()
    {
        // T1 contiene C e H; T3 contiene H (stesso percorso) e un altro file di libreria D.
        var index = Index(
            [Torrent("t1"), Torrent("t3")],
            ("t1", "/dl/c.mkv", 1), ("t1", "/dl/h.mkv", 2), ("t3", "/dl/h.mkv", 2), ("t3", "/dl/d.mkv", 3));
        var library = new HashSet<FileId> { Id(1), Id(2), Id(3) };

        var result = SpaceMath.Estimate([Fact(1, 2), Fact(2, 2)], index, library, Settings, Now);

        Assert.Equal(10 * Gb, result.InPackBytes);
        Assert.Equal(0, result.FreeNowBytes);
        Assert.Equal(0, result.FreeLaterBytes);
        Assert.Empty(result.RemoveNow);
        Assert.Empty(result.RemoveLater);
    }

    [Fact]
    public void CrossSeedWithOneProtectedHolderFreesLater()
    {
        var index = Index(
            [Torrent("a"), Torrent("b", "itatorrents.xyz", 1, 5 * 86_400)],
            ("a", "/dl/1.mkv", 1), ("b", "/dl/1.mkv", 1));

        var result = SpaceMath.Estimate([Fact(1, 2)], index, new HashSet<FileId> { Id(1) }, Settings, Now);

        Assert.Equal(0, result.FreeNowBytes);
        Assert.Equal(5 * Gb, result.FreeLaterBytes);
        Assert.Equal(DateTimeOffset.Parse("2026-11-24T12:00:00Z"), result.FreeLaterAt);
        Assert.Equal(["a"], result.RemoveNow);
        Assert.Equal(["b"], result.RemoveLater);
    }

    [Fact]
    public void AHolderMissingFromTheTorrentListKeepsTheBytes()
    {
        var index = Index([], ("ghost", "/dl/1.mkv", 1));

        var result = SpaceMath.Estimate([Fact(1, 2)], index, new HashSet<FileId> { Id(1) }, Settings, Now);

        Assert.Equal(5 * Gb, result.InPackBytes);
        Assert.Empty(result.RemoveNow);
    }

    [Fact]
    public void AnUnknownTorrentIsNeverTorrentOnly()
    {
        Assert.False(SpaceMath.IsTorrentOnly("nope", Index([]), new Dictionary<FileId, int>()));
    }

    [Fact]
    public void TorrentOnlyMeansNoLibraryLink()
    {
        var index = Index([Torrent("a")], ("a", "/dl/1.mkv", 1));

        Assert.True(SpaceMath.IsTorrentOnly("a", index, new Dictionary<FileId, int> { [Id(1)] = 1 }));
        Assert.False(SpaceMath.IsTorrentOnly("a", index, new Dictionary<FileId, int> { [Id(1)] = 2 }));
    }
}
