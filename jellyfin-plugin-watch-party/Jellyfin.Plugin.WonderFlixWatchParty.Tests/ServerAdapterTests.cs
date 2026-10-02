using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;
using MediaBrowser.Model.Session;
using MediaBrowser.Model.SyncPlay;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ServerAdapterTests
{
    private static SessionInfo Session(string id, string deviceId, string client, Guid userId, string userName) =>
        new(null!, NullLogger.Instance)
        {
            Id = id,
            DeviceId = deviceId,
            Client = client,
            UserId = userId,
            UserName = userName,
        };

    [Fact]
    public void FindsTheCallerByDeviceClientAndUser()
    {
        var userId = Guid.NewGuid();
        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        var web = Session("s-web", "d1", "Jellyfin Web", userId, "Mario");
        var app = Session("s-app", "d1", "WonderFlix", userId, "Mario");
        stub.Handlers["get_Sessions"] = _ => new[] { web, app };
        var directory = new JellyfinSessionDirectory(manager);

        Assert.Equal(new CallerSession("s-app", userId, "Mario"), directory.FindCaller("d1", "WonderFlix", userId));
        Assert.Null(directory.FindCaller("d1", "WonderFlix", Guid.NewGuid()));
        Assert.Null(directory.FindCaller(null, "WonderFlix", userId));
        Assert.Null(directory.FindCaller("d1", "WonderFlix", Guid.Empty));
        Assert.True(directory.Exists("s-web"));
        Assert.False(directory.Exists("s-x"));
    }

    [Fact]
    public void ParticipantsComeFromSyncPlay()
    {
        var group = Guid.NewGuid();
        var (manager, sessions) = InterfaceStub<ISessionManager>.Create();
        var mario = Session("s1", "d1", "WonderFlix", Guid.NewGuid(), "Mario");
        sessions.Handlers["get_Sessions"] = _ => new[] { mario };
        var (syncPlay, groups) = InterfaceStub<ISyncPlayManager>.Create();
        groups.Handlers["GetGroup"] = args => ReferenceEquals(args[0], mario) && (Guid)args[1]! == group
            ? new GroupInfoDto(group, "Mario · Dune", GroupStateType.Paused, new[] { "Mario", "Luigi" }, DateTime.UtcNow)
            : null;
        var directory = new JellyfinGroupDirectory(manager, syncPlay);

        Assert.Equal(new[] { "Mario", "Luigi" }, directory.GetParticipants("s1", group));
        Assert.Null(directory.GetParticipants("s1", Guid.NewGuid()));
        Assert.Null(directory.GetParticipants("s-x", group));
    }

    [Fact]
    public async Task SenderUsesSendStringWithoutAControllingSession()
    {
        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        var sender = new JellyfinEventSender(manager);

        Assert.True(await sender.TrySendAsync("s1", "{\"Type\":\"Chat\"}", CancellationToken.None));
        var call = Assert.Single(stub.Calls, c => c.Name == "SendGeneralCommand");
        Assert.Null(call.Args[0]);
        Assert.Equal("s1", call.Args[1]);
        var command = Assert.IsType<GeneralCommand>(call.Args[2]);
        Assert.Equal(GeneralCommandType.SendString, command.Name);
        Assert.Equal("{\"Type\":\"Chat\"}", command.Arguments["WonderFlixWatchParty"]);

        stub.Handlers["SendGeneralCommand"] =
            _ => Task.FromException(new ResourceNotFoundException("Session s2 not found."));
        Assert.False(await sender.TrySendAsync("s2", "{}", CancellationToken.None));
    }
}
