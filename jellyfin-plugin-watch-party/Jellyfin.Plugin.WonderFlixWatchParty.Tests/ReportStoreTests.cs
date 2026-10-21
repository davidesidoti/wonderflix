using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ReportStoreTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 21, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private ReportStore Store() => new(_folder.ReportsFile, NullLogger<ReportStore>.Instance);

    private void WriteRaw(string json)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.ReportsFile)!);
        File.WriteAllText(_folder.ReportsFile, json);
    }

    [Fact]
    public void AMissingFileIsEmpty()
    {
        Assert.Empty(Store().Load().All());
        Assert.False(File.Exists(_folder.ReportsFile));
    }

    [Fact]
    public void TheSavedFileHasTheSpecShape()
    {
        var report = new StoredReport(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), ReportTypes.Subtitles, null, T0, T0);
        var book = new ReportBook();
        book.Add(report);

        Store().Save(book);

        Assert.False(File.Exists(_folder.ReportsFile + ".tmp"));
        using var doc = JsonDocument.Parse(File.ReadAllText(_folder.ReportsFile));
        Assert.Equal(1, doc.RootElement.GetProperty("Version").GetInt32());
        var entry = doc.RootElement.GetProperty("Reports")[0];
        Assert.Equal(report.Id.ToString("N"), entry.GetProperty("Id").GetString());
        Assert.Equal(report.UserId.ToString("N"), entry.GetProperty("UserId").GetString());
        Assert.Equal(report.ItemId.ToString("N"), entry.GetProperty("ItemId").GetString());
        Assert.Equal("Subtitles", entry.GetProperty("Type").GetString());
        Assert.True(entry.TryGetProperty("CreatedAt", out _));
        Assert.True(entry.TryGetProperty("UpdatedAt", out _));
        Assert.False(entry.TryGetProperty("Note", out _));
        Assert.Equal(report, Store().Load().Get(report.Id));
    }

    [Fact]
    public void AnUnreadableFileGoesToBad()
    {
        WriteRaw("{nope");
        Assert.Empty(Store().Load().All());
        Assert.True(File.Exists(_folder.ReportsFile + ".bad"));
    }

    [Fact]
    public void AnUnknownTypeMakesTheFileUnreadable()
    {
        var (id, mario, item) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        WriteRaw($$$"""
            {"Version":1,"Reports":[{"Id":"{{{id:N}}}","UserId":"{{{mario:N}}}","ItemId":"{{{item:N}}}","Type":"Boh","CreatedAt":"2026-10-21T20:00:00+00:00","UpdatedAt":"2026-10-21T20:00:00+00:00"}]}
            """);
        Assert.Empty(Store().Load().All());
        Assert.True(File.Exists(_folder.ReportsFile + ".bad"));
    }
}
