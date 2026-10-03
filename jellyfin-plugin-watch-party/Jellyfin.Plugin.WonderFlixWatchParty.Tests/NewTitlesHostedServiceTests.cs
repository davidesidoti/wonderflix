using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class NewTitlesHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly NewTitlesCollector _collector;
    private readonly UserRef _mario;
    private readonly ILibraryManager _library;
    private readonly InterfaceStub<ILibraryManager> _stub;
    private EventHandler<ItemChangeEventArgs>? _added;
    private EventHandler<ItemChangeEventArgs>? _removed;

    public NewTitlesHostedServiceTests()
    {
        _collector = TestNewTitles.Create(_server, TestInbox.Create(_server, _folder, _time), _time);
        _mario = _server.AddUser("Mario");
        (_library, _stub) = InterfaceStub<ILibraryManager>.Create();
        _stub.Handlers["add_ItemAdded"] = args =>
        {
            _added = (EventHandler<ItemChangeEventArgs>?)args[0];
            return null;
        };
        _stub.Handlers["add_ItemRemoved"] = args =>
        {
            _removed = (EventHandler<ItemChangeEventArgs>?)args[0];
            return null;
        };
    }

    public void Dispose()
    {
        _collector.Dispose();
        _folder.Dispose();
    }

    private async Task<NewTitlesHostedService> StartAsync()
    {
        var service = new NewTitlesHostedService(_library, _collector, NullLogger<NewTitlesHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);
        Assert.NotNull(_added);
        Assert.NotNull(_removed);
        return service;
    }

    [Fact]
    public async Task OnlyRealTitlesReachTheCollectorAndPlaceholdersDoNotHideEpisodes()
    {
        var service = await StartAsync();
        var seriesId = Guid.NewGuid();
        // TVDB toglie il segnaposto dell'episodio mancante quando arriva quello
        // vero, con lo stesso id TVDB: non è una sostituzione.
        var placeholder = new Episode { Id = Guid.NewGuid(), IsVirtualItem = true, SeriesId = seriesId };
        placeholder.ProviderIds["Tvdb"] = "42";
        var real = new Episode { Id = Guid.NewGuid(), Path = "/media/tv/e1.mkv", SeriesId = seriesId };

        _removed!(_library, new ItemChangeEventArgs { Item = placeholder });
        _added!(_library, new ItemChangeEventArgs { Item = real });
        _added(_library, new ItemChangeEventArgs { Item = placeholder });
        _added(_library, new ItemChangeEventArgs { Item = new Series { Id = Guid.NewGuid(), Path = "/media/tv/The Bear" } });
        Assert.Equal(1, _collector.Pending);

        _server.Titles[real.Id] = new LibraryTitle(
            real.Id, false, "Pilot", null, seriesId, "The Bear", "bear-key", 1, 1, ["Tvdb:42"], true);
        _server.Following.Add((_mario.Id, seriesId));
        Assert.Equal(new Protocol.NewTitlesSendResponse(1, 1), await _collector.SendNowAsync());

        await service.StopAsync(CancellationToken.None);
        Assert.Contains(_stub.Calls, c => c.Name == "remove_ItemAdded");
        Assert.Contains(_stub.Calls, c => c.Name == "remove_ItemRemoved");
    }

    [Fact]
    public async Task ARealTitleRemovedAndAddedAgainIsAReplacement()
    {
        await StartAsync();
        var old = new Movie { Id = Guid.NewGuid(), Path = "/media/film/dune.720p.mkv" };
        old.ProviderIds["Tmdb"] = "438631";
        var better = new Movie { Id = Guid.NewGuid(), Path = "/media/film/dune.2160p.mkv" };

        _removed!(_library, new ItemChangeEventArgs { Item = old });
        _added!(_library, new ItemChangeEventArgs { Item = better });
        _server.Titles[better.Id] = new LibraryTitle(
            better.Id, true, "Dune", 2021, Guid.Empty, string.Empty, string.Empty, null, null, ["Tmdb:438631"], true);

        Assert.Equal(new Protocol.NewTitlesSendResponse(0, 0), await _collector.SendNowAsync());
    }
}
