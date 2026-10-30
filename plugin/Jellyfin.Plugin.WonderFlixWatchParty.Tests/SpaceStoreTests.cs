using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SpaceStoreTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 30, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private SpaceStore Store() => new(_folder.SpaceFile, NullLogger<SpaceStore>.Instance);

    private static SpaceOperation Operation(string id, DateTimeOffset at) => new()
    {
        Id = id,
        Kind = SpaceKinds.Movie,
        Key = "movie:12",
        Title = "Coco",
        State = SpaceOperationStates.Done,
        StartedAt = at,
        EndedAt = at.AddMinutes(1),
        EstimatedFreedBytes = 6_000,
        PendingBytes = 2_000,
        QuotaBeforeBytes = 10_000,
        QuotaAfterBytes = 4_000,
        Steps =
        [
            new SpaceStep { Name = SpaceSteps.FindTorrents, State = SpaceStepStates.Done, Done = 1, Waiting = 1 },
            new SpaceStep { Name = SpaceSteps.RemoveFromSeerr, State = SpaceStepStates.Skipped, Detail = SpaceDetails.NotConfigured },
        ],
    };

    [Fact]
    public void TheFileRoundTrips()
    {
        var book = new SpaceBook();
        book.Keep("movie:12", "Coco");
        book.AddPending(new PendingTorrent
        {
            Hash = "h1", Name = "Coco.2017", Tracker = "itatorrents.xyz", SizeBytes = 2_000, ExpectedAt = Now.AddDays(3), Title = "Coco",
        });
        book.AddOperation(Operation("op1", Now));

        Store().Save(book);
        var loaded = Store().Load();

        Assert.False(File.Exists(_folder.SpaceFile + ".tmp"));
        Assert.Equal(JsonSerializer.Serialize(book.ToFile()), JsonSerializer.Serialize(loaded.ToFile()));
        Assert.True(loaded.IsKept("movie:12"));
        Assert.Equal("h1", Assert.Single(loaded.Pending).Hash);
        Assert.Equal(2, Assert.Single(loaded.Operations).Steps.Count);
    }

    [Theory]
    [InlineData("""{"Version":2}""")]
    [InlineData("""{"Version":1,"Kept":null}""")]
    [InlineData("""{"Version":1,"Operations":[{"Id":"a","Steps":null}]}""")]
    [InlineData("""{"Version":1,"Kept":[{"Key":null,"Title":"Coco"}]}""")]
    [InlineData("""{"Version":1,"Kept":[{"Key":"movie:1","Title":null}]}""")]
    [InlineData("""{"Version":1,"Pending":[{"Hash":null}]}""")]
    [InlineData("""{"Version":1,"Pending":[{"Hash":"h1","Name":null}]}""")]
    [InlineData("""{"Version":1,"Pending":[{"Hash":"h1","Title":null}]}""")]
    [InlineData("""{"Version":1,"Operations":[{"Id":"a","Key":null,"Steps":[]}]}""")]
    [InlineData("""{"Version":1,"Operations":[{"Id":"a","Title":null,"Steps":[]}]}""")]
    [InlineData("""{"Version":1,"Operations":[{"Id":"a","Steps":[{"Name":null}]}]}""")]
    [InlineData("{nope")]
    public void ABrokenFileStartsEmpty(string json)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.SpaceFile)!);
        File.WriteAllText(_folder.SpaceFile, json);

        var book = Store().Load();

        Assert.Empty(book.Kept);
        Assert.Empty(book.Pending);
        Assert.Empty(book.Operations);
        Assert.True(File.Exists(_folder.SpaceFile + ".bad"));
        Assert.False(File.Exists(_folder.SpaceFile));
    }

    [Fact]
    public void OldOperationsArePruned()
    {
        var book = new SpaceBook();
        book.AddOperation(Operation("old", Now.AddDays(-31)));
        book.AddOperation(Operation("recent", Now.AddDays(-29)));

        book.Prune(Now);

        Assert.Equal("recent", Assert.Single(book.Operations).Id);
    }

    [Fact]
    public void OperationsAreNewestFirstAndPendingHasNoDoubles()
    {
        var book = new SpaceBook();
        book.AddOperation(Operation("first", Now));
        book.AddOperation(Operation("second", Now));
        book.AddPending(new PendingTorrent { Hash = "h1", Title = "A" });
        book.AddPending(new PendingTorrent { Hash = "h1", Title = "B" });

        Assert.Equal(["second", "first"], book.Operations.Select(o => o.Id));
        Assert.Equal("A", Assert.Single(book.Pending).Title);
        Assert.True(book.RemovePending("h1"));
        Assert.False(book.RemovePending("h1"));
    }
}
