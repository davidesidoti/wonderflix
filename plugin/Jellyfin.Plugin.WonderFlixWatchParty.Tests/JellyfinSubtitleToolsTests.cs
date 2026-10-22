using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Providers;
using MediaBrowser.Controller.Subtitles;
using MediaBrowser.Model.IO;
using MediaBrowser.Model.Providers;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class JellyfinSubtitleToolsTests
{
    private readonly Dictionary<Guid, BaseItem> _items = [];
    private readonly InterfaceStub<ISubtitleManager> _subtitles;
    private readonly InterfaceStub<IProviderManager> _providers;
    private readonly JellyfinSubtitleTools _tools;
    private readonly RecordingLogger<JellyfinSubtitleTools> _logger = new();

    public JellyfinSubtitleToolsTests()
    {
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemById"] = args => _items.GetValueOrDefault((Guid)args[0]!);
        var (subtitleManager, subtitles) = InterfaceStub<ISubtitleManager>.Create();
        var (providerManager, providers) = InterfaceStub<IProviderManager>.Create();
        var (fileSystem, _) = InterfaceStub<IFileSystem>.Create();
        _subtitles = subtitles;
        _providers = providers;
        _tools = new JellyfinSubtitleTools(libraryManager, subtitleManager, providerManager, fileSystem, _logger);
    }

    private T Add<T>(T item) where T : BaseItem
    {
        item.Id = Guid.NewGuid();
        _items[item.Id] = item;
        return item;
    }

    [Fact]
    public async Task SearchMapsTheResults()
    {
        var movie = Add(new Movie());
        _subtitles.Handlers["SearchSubtitles"] = _ => Task.FromResult(new[]
        {
            new RemoteSubtitleInfo
            {
                Id = "abc", ProviderName = "OpenSubtitles", Name = "Dune.2021", ThreeLetterISOLanguageName = "ita", Format = "srt",
                CommunityRating = 7.5f, DownloadCount = 12, IsHashMatch = null, AiTranslated = true, MachineTranslated = false,
                Forced = null, HearingImpaired = true,
            },
        });

        var found = await _tools.SearchAsync(movie.Id, "ita", true, CancellationToken.None);

        Assert.Equal(
            new RemoteSubtitleDto("abc", "OpenSubtitles", "Dune.2021", "ita", "srt", 7.5f, 12, false, true, false, true),
            Assert.Single(found));
        var call = Assert.Single(_subtitles.Calls, c => c.Name == "SearchSubtitles");
        Assert.Same(movie, call.Args[0]);
        Assert.Equal("ita", call.Args[1]);
        Assert.Equal(true, call.Args[2]);
        Assert.Equal(false, call.Args[3]);
    }

    [Fact]
    public async Task SearchWithoutTheFlagsIsFalse()
    {
        var movie = Add(new Movie());
        _subtitles.Handlers["SearchSubtitles"] = _ => Task.FromResult(new[] { new RemoteSubtitleInfo { Id = "x" } });

        var dto = Assert.Single(await _tools.SearchAsync(movie.Id, "eng", null, CancellationToken.None));

        Assert.False(dto.IsHashMatch || dto.HearingImpaired || dto.Forced || dto.MachineTranslated);
        Assert.Equal(string.Empty, dto.ProviderName);
        Assert.Equal(string.Empty, dto.Language);
    }

    [Fact]
    public async Task DownloadQueuesARefreshOnlyOnSuccess()
    {
        var episode = Add(new Episode());

        await _tools.DownloadAsync(episode.Id, "sub-1", CancellationToken.None);

        var download = Assert.Single(_subtitles.Calls, c => c.Name == "DownloadSubtitles");
        Assert.Same(episode, download.Args[0]);
        Assert.Equal("sub-1", download.Args[1]);
        var refresh = Assert.Single(_providers.Calls, c => c.Name == "QueueRefresh");
        Assert.Equal(episode.Id, refresh.Args[0]);
        Assert.Equal(RefreshPriority.High, refresh.Args[2]);

        _providers.Calls.Clear();
        _subtitles.Handlers["DownloadSubtitles"] = _ => Task.FromException(new InvalidOperationException("provider down"));
        await Assert.ThrowsAsync<InvalidOperationException>(() => _tools.DownloadAsync(episode.Id, "sub-2", CancellationToken.None));
        Assert.DoesNotContain(_providers.Calls, c => c.Name == "QueueRefresh");
    }

    [Fact]
    public async Task ARefreshErrorAfterASavedSubtitleDoesNotFailTheCall()
    {
        var episode = Add(new Episode());
        _providers.Handlers["QueueRefresh"] = _ => throw new InvalidOperationException("coda piena");

        await _tools.DownloadAsync(episode.Id, "sub-1", CancellationToken.None);
        await _tools.UploadAsync(episode.Id, new SubtitleUpload("ita", "srt", false, false, [1]), CancellationToken.None);

        Assert.Equal(2, _logger.Entries.Count(e => e.Level == Microsoft.Extensions.Logging.LogLevel.Warning));
        Assert.All(_logger.Entries, e => Assert.Contains(episode.Id.ToString("N"), e.Message));
    }

    [Fact]
    public async Task UploadPassesTheFileAndQueuesARefresh()
    {
        var movie = Add(new Movie());
        SubtitleResponse? sent = null;
        byte[]? bytes = null;
        _subtitles.Handlers["UploadSubtitle"] = args =>
        {
            sent = (SubtitleResponse)args[1]!;
            using var copy = new MemoryStream();
            sent.Stream.CopyTo(copy);
            bytes = copy.ToArray();
            return Task.CompletedTask;
        };

        await _tools.UploadAsync(movie.Id, new SubtitleUpload("ita", "srt", true, false, [1, 2, 3]), CancellationToken.None);

        Assert.NotNull(sent);
        Assert.Equal("ita", sent.Language);
        Assert.Equal("srt", sent.Format);
        Assert.True(sent.IsForced);
        Assert.False(sent.IsHearingImpaired);
        Assert.Equal(new byte[] { 1, 2, 3 }, bytes);
        Assert.Same(movie, _subtitles.Calls.Single(c => c.Name == "UploadSubtitle").Args[0]);
        var refresh = Assert.Single(_providers.Calls, c => c.Name == "QueueRefresh");
        Assert.Equal(movie.Id, refresh.Args[0]);
        Assert.Equal(RefreshPriority.High, refresh.Args[2]);
    }

    [Fact]
    public async Task UploadThatThrowsQueuesNoRefresh()
    {
        var movie = Add(new Movie());
        _subtitles.Handlers["UploadSubtitle"] = _ => Task.FromException(new ArgumentException("formato"));

        await Assert.ThrowsAsync<ArgumentException>(
            () => _tools.UploadAsync(movie.Id, new SubtitleUpload("ita", "srt", false, false, [1]), CancellationToken.None));
        Assert.DoesNotContain(_providers.Calls, c => c.Name == "QueueRefresh");
    }

    [Fact]
    public void IsVideoOnlyForMoviesAndEpisodes()
    {
        Assert.True(_tools.IsVideo(Add(new Movie()).Id));
        Assert.True(_tools.IsVideo(Add(new Episode()).Id));
        Assert.False(_tools.IsVideo(Add(new Series()).Id));
        Assert.False(_tools.IsVideo(Add(new Season()).Id));
        Assert.False(_tools.IsVideo(Guid.NewGuid()));
        Assert.False(_tools.IsVideo(Guid.Empty));
    }

    [Fact]
    public async Task ANonVideoIsRejected()
    {
        var series = Add(new Series());

        await Assert.ThrowsAsync<InvalidOperationException>(() => _tools.SearchAsync(series.Id, "ita", null, CancellationToken.None));
        await Assert.ThrowsAsync<InvalidOperationException>(() => _tools.DownloadAsync(series.Id, "x", CancellationToken.None));
        await Assert.ThrowsAsync<InvalidOperationException>(
            () => _tools.UploadAsync(series.Id, new SubtitleUpload("ita", "srt", false, false, [1]), CancellationToken.None));
        Assert.Empty(_subtitles.Calls);
    }
}
