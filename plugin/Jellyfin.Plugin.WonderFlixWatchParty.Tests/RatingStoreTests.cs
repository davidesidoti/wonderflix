using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RatingStoreTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 20, 21, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private RatingStore Store() => new(_folder.RatingsFile, NullLogger<RatingStore>.Instance);

    private void WriteRaw(string json)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.RatingsFile)!);
        File.WriteAllText(_folder.RatingsFile, json);
    }

    [Fact]
    public void AMissingFileIsEmpty()
    {
        Assert.Empty(Store().Load().ForItem(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.RatingsFile));
    }

    [Fact]
    public void TheSavedFileHasTheSpecShape()
    {
        var (film, mario) = (Guid.NewGuid(), Guid.NewGuid());
        var book = new RatingBook();
        var stored = book.Set(film, mario, 8, null, T0);

        Store().Save(book);

        Assert.False(File.Exists(_folder.RatingsFile + ".tmp"));
        using var doc = JsonDocument.Parse(File.ReadAllText(_folder.RatingsFile));
        Assert.Equal(1, doc.RootElement.GetProperty("Version").GetInt32());
        var entry = doc.RootElement.GetProperty("Items").GetProperty(film.ToString("N"))[0];
        Assert.Equal(mario.ToString("N"), entry.GetProperty("UserId").GetString());
        Assert.Equal(8, entry.GetProperty("Score").GetInt32());
        Assert.True(entry.TryGetProperty("CreatedAt", out _));
        Assert.True(entry.TryGetProperty("UpdatedAt", out _));
        Assert.False(entry.TryGetProperty("Comment", out _));
        Assert.Equal(stored, Store().Load().Get(film, mario));
    }

    [Fact]
    public void AnUnreadableFileGoesToBad()
    {
        WriteRaw("{nope");
        Assert.Empty(Store().Load().ForItem(Guid.NewGuid()));
        Assert.True(File.Exists(_folder.RatingsFile + ".bad"));
    }

    [Fact]
    public void AScoreOutsideOneToTenMakesTheFileUnreadable()
    {
        var (film, mario) = (Guid.NewGuid(), Guid.NewGuid());
        WriteRaw($$$"""
            {"Version":1,"Items":{"{{{film:N}}}":[{"UserId":"{{{mario:N}}}","Score":11,"CreatedAt":"2026-10-20T21:00:00+00:00","UpdatedAt":"2026-10-20T21:00:00+00:00"}]}}
            """);
        Assert.Empty(Store().Load().ForItem(film));
        Assert.True(File.Exists(_folder.RatingsFile + ".bad"));
    }
}
