using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadStoreTests : IDisposable
{
    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private void WriteRaw(string json)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.DownloadsFile)!);
        File.WriteAllText(_folder.DownloadsFile, json);
    }

    [Fact]
    public void AMissingFileStartsEmpty()
    {
        Assert.Empty(Store().Load().Entries);
        Assert.False(File.Exists(_folder.DownloadsFile));
    }

    [Fact]
    public void SaveThenLoad()
    {
        var book = new DownloadBook();
        book.Put(new DownloadEntry { Key = "movie:1", Title = "Film", State = "Waiting" });
        book.Accept("movie:2");

        Store().Save(book);

        Assert.False(File.Exists(_folder.DownloadsFile + ".tmp"));
        var loaded = Store().Load();
        Assert.Equal("Film", loaded.Get("movie:1")!.Title);
        Assert.True(loaded.IsAccepted("movie:2"));
    }

    [Fact]
    public void ABrokenFileStartsEmpty()
    {
        WriteRaw("{nope");

        Assert.Empty(Store().Load().Entries);
        Assert.True(File.Exists(_folder.DownloadsFile + ".bad"));
        Assert.False(File.Exists(_folder.DownloadsFile));
    }

    [Fact]
    public void AFutureVersionStartsEmpty()
    {
        WriteRaw("""{"Version":2,"Entries":[{"Key":"movie:1"}]}""");

        Assert.Empty(Store().Load().Entries);
        Assert.True(File.Exists(_folder.DownloadsFile + ".bad"));
    }
}
