using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Dto;
using MediaBrowser.Model.Session;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PlaybackAdapterTests
{
    private static SessionInfo Session(ISessionManager manager, string id, string client, Guid userId) =>
        new(manager, NullLogger.Instance) { Id = id, DeviceId = id, Client = client, UserId = userId };

    [Fact]
    public void OnlyMoviesAndEpisodesArePlayingTitles()
    {
        var movie = new Movie { Id = Guid.NewGuid(), Name = "Dune" };
        var series = Guid.NewGuid();
        var episode = new Episode
        {
            Id = Guid.NewGuid(), Name = "Pilot", SeriesId = series, SeriesName = "The Bear", ParentIndexNumber = 2, IndexNumber = 3,
        };
        var orphan = new Episode { Id = Guid.NewGuid(), Name = "Speciale" };

        Assert.Equal(new PlayingTitle(movie.Id, "Dune", movie.Id, null, null, null, null), PlayingTitles.From(movie));
        Assert.Equal(new PlayingTitle(episode.Id, "Pilot", series, series, "The Bear", 2, 3), PlayingTitles.From(episode));
        Assert.Equal(new PlayingTitle(orphan.Id, "Speciale", null, null, null, null, null), PlayingTitles.From(orphan));
        Assert.Null(PlayingTitles.From(new Trailer { Id = Guid.NewGuid() }));
        Assert.Null(PlayingTitles.From(new Series { Id = Guid.NewGuid() }));
        Assert.Null(PlayingTitles.From(null));
    }

    [Fact]
    public void OnlyRealWonderFlixReportsCount()
    {
        var (manager, _) = InterfaceStub<ISessionManager>.Create();
        var userId = Guid.NewGuid();
        var movie = new Movie { Id = Guid.NewGuid() };
        var checkIn = new DateTime(2026, 10, 13, 20, 0, 0, DateTimeKind.Utc);
        SessionInfo WithCheckIn(string client)
        {
            var session = Session(manager, "s-1", client, userId);
            session.LastPlaybackCheckIn = checkIn;
            return session;
        }

        PlaybackProgressEventArgs Progress(string client, bool automated = false) => new()
        {
            Session = WithCheckIn(client),
            Item = movie,
            PlaybackPositionTicks = 42,
            IsAutomated = automated,
        };

        Assert.Equal(new PlaybackReport("s-1", userId, movie.Id, 42, false, checkIn), PlayingTitles.Report(Progress("WonderFlix")));
        Assert.Null(PlayingTitles.Report(Progress("Jellyfin Web")));
        Assert.Null(PlayingTitles.Report(Progress("WonderFlix", automated: true)));
        Assert.Null(PlayingTitles.Report(new PlaybackProgressEventArgs { Session = Session(manager, "s-1", "WonderFlix", Guid.Empty), Item = movie }));
        Assert.Null(PlayingTitles.Report(new PlaybackProgressEventArgs { Session = Session(manager, "s-1", "WonderFlix", userId), Item = new Trailer() }));

        var stopped = new PlaybackStopEventArgs
        {
            Session = WithCheckIn("WonderFlix"), Item = movie, PlaybackPositionTicks = null, PlayedToCompletion = true,
        };
        Assert.Equal(new PlaybackReport("s-1", userId, movie.Id, 0, true, checkIn), PlayingTitles.Report(stopped));
    }

    [Fact]
    public void ThePlaybackDirectoryListsWonderFlixSessionsThatPlay()
    {
        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        var mario = Guid.NewGuid();
        var movie = new Movie { Id = Guid.NewGuid(), Name = "Dune" };
        var fromDto = new Movie { Id = Guid.NewGuid(), Name = "Alien" };
        var checkIn = new DateTime(2026, 10, 13, 20, 0, 0, DateTimeKind.Utc);

        var playing = Session(manager, "s-1", "WonderFlix", mario);
        playing.FullNowPlayingItem = movie;
        playing.PlayState = new PlayerStateInfo { PositionTicks = 600 };
        playing.LastPlaybackCheckIn = checkIn;
        var web = Session(manager, "s-2", "Jellyfin Web", mario);
        web.FullNowPlayingItem = movie;
        var idle = Session(manager, "s-3", "WonderFlix", mario);
        var trailer = Session(manager, "s-4", "WonderFlix", mario);
        trailer.FullNowPlayingItem = new Trailer { Id = Guid.NewGuid() };
        var dtoOnly = Session(manager, "s-5", "WonderFlix", mario);
        dtoOnly.NowPlayingItem = new BaseItemDto { Id = fromDto.Id };
        stub.Handlers["get_Sessions"] = _ => new[] { playing, web, idle, trailer, dtoOnly };
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemById"] = args => (Guid)args[0]! == fromDto.Id ? fromDto : null;

        var list = new JellyfinPlaybackDirectory(manager, libraryManager).GetAppPlayback();

        Assert.Equal(2, list.Count);
        Assert.Equal(
            new AppPlayback("s-1", mario, new PlayingTitle(movie.Id, "Dune", movie.Id, null, null, null, null), 600, new DateTimeOffset(checkIn)),
            list[0]);
        Assert.Equal("s-5", list[1].SessionId);
        Assert.Equal(fromDto.Id, list[1].Item.ItemId);
        Assert.Equal(0, list[1].PositionTicks);
    }
}
