using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class TrailerCacheTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "wf-trailer-cache-" + Guid.NewGuid().ToString("N"));
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero));

    public void Dispose()
    {
        if (Directory.Exists(_folder))
        {
            Directory.Delete(_folder, true);
        }
    }

    private TrailerCache Cache() => new(_folder, _time);

    private static void Write(TrailerCache cache, string id, long length = 3)
    {
        using var stream = File.Create(cache.PathFor(id));
        stream.SetLength(length);
    }

    [Fact]
    public void SweepDeletesFilesUnseenForAnHour()
    {
        var cache = Cache();
        Write(cache, "a");
        cache.Touch("a");

        _time.Advance(TimeSpan.FromMinutes(59));
        cache.Sweep();
        Assert.True(File.Exists(cache.PathFor("a")));

        _time.Advance(TimeSpan.FromMinutes(2));
        cache.Sweep();
        Assert.False(File.Exists(cache.PathFor("a")));
    }

    [Fact]
    public void TouchKeepsAFileAlive()
    {
        var cache = Cache();
        Write(cache, "a");
        cache.Touch("a");

        _time.Advance(TimeSpan.FromMinutes(50));
        cache.Touch("a");
        _time.Advance(TimeSpan.FromMinutes(20));
        cache.Sweep();

        Assert.True(File.Exists(cache.PathFor("a")));
    }

    [Fact]
    public void HasTouchesTheFile()
    {
        var cache = Cache();
        Write(cache, "a");
        cache.Touch("a");

        _time.Advance(TimeSpan.FromMinutes(50));
        Assert.True(cache.Has("a"));
        Assert.False(cache.Has("missing"));
        _time.Advance(TimeSpan.FromMinutes(20));
        cache.Sweep();

        Assert.True(File.Exists(cache.PathFor("a")));
    }

    [Fact]
    public void AnOpenLeaseBlocksDeletion()
    {
        var cache = Cache();
        Write(cache, "a");
        cache.Touch("a");
        var lease = cache.OpenLease("a");

        _time.Advance(TimeSpan.FromHours(2));
        cache.Sweep();
        Assert.True(File.Exists(cache.PathFor("a")));

        lease.Dispose();
        _time.Advance(TimeSpan.FromHours(2));
        cache.Sweep();
        Assert.False(File.Exists(cache.PathFor("a")));
    }

    [Fact]
    public void SweepRemovesOrphanParts()
    {
        var cache = Cache();
        var old = Path.Combine(_folder, "x.part.mp4");
        var fresh = Path.Combine(_folder, "y.part.mp4");
        File.WriteAllText(old, "x");
        File.WriteAllText(fresh, "y");
        File.SetLastWriteTimeUtc(old, _time.GetUtcNow().UtcDateTime.AddMinutes(-11));
        File.SetLastWriteTimeUtc(fresh, _time.GetUtcNow().UtcDateTime.AddMinutes(-5));

        cache.Sweep();

        Assert.False(File.Exists(old));
        Assert.True(File.Exists(fresh));
    }

    [Fact]
    public void ClearEmptiesTheFolder()
    {
        var cache = Cache();
        Write(cache, "a");
        File.WriteAllText(Path.Combine(_folder, "b.part.mp4"), "x");

        cache.Clear();

        Assert.Empty(Directory.GetFiles(_folder));
    }

    private TrailerCache ThreeBigFiles()
    {
        var cache = Cache();
        foreach (var id in new[] { "a", "b", "c" })
        {
            Write(cache, id, 400L << 20);
            cache.Touch(id);
            _time.Advance(TimeSpan.FromMinutes(1));
        }

        return cache;
    }

    [Fact]
    public void MakeRoomDropsTheLeastRecentlySeen()
    {
        var cache = ThreeBigFiles();
        cache.Touch("a"); // ora il meno visto è b, poi c

        cache.MakeRoom(400L << 20);

        Assert.False(File.Exists(cache.PathFor("b")));
        Assert.False(File.Exists(cache.PathFor("c")));
        Assert.True(File.Exists(cache.PathFor("a")));
    }

    [Fact]
    public void MakeRoomStopsAsSoonAsItFits()
    {
        var cache = ThreeBigFiles();

        cache.MakeRoom(200L << 20); // 1200 + 200 > 1024: via il più vecchio basta? 800 + 200 <= 1024

        Assert.False(File.Exists(cache.PathFor("a")));
        Assert.True(File.Exists(cache.PathFor("b")));
        Assert.True(File.Exists(cache.PathFor("c")));
    }

    [Fact]
    public void MakeRoomNeverDropsALeasedFile()
    {
        var cache = ThreeBigFiles();

        using var lease = cache.OpenLease("a");
        cache.MakeRoom(400L << 20);

        Assert.True(File.Exists(cache.PathFor("a")));
        Assert.False(File.Exists(cache.PathFor("b")));
        Assert.False(File.Exists(cache.PathFor("c")));
    }
}
