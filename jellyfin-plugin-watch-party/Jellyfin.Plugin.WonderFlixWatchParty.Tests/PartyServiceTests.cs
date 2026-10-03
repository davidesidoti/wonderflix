using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PartyServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FriendService _friends;
    private readonly PartyRegistry _registry = new();
    private readonly PartyService _service;
    private readonly Guid _group = Guid.NewGuid();
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly CallerSession _marioSession;
    private readonly CallerSession _luigiSession;
    private readonly CallerSession _peachSession;

    public PartyServiceTests()
    {
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
        _service = new PartyService(
            new PartyDirectory(_time), _server, _server, _server, _friends, _registry, _server,
            new RateLimiter(_time), NullLogger<PartyService>.Instance);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _marioSession = _server.AddSession("s-mario", _mario);
        _luigiSession = _server.AddSession("s-luigi", _luigi);
        _peachSession = _server.AddSession("s-peach", _peach);
        _server.Groups[_group] = ["Mario"];
        _server.GroupNames[_group] = "Mario · Dune";
    }

    public void Dispose() => _folder.Dispose();

    private static string Type(string payload) => JsonDocument.Parse(payload).RootElement.GetProperty("Type").GetString()!;

    private async Task MakeFriends(UserRef a, UserRef b)
    {
        await _friends.RequestAsync(a.Id, b.Id);
        await _friends.AcceptAsync(b.Id, a.Id);
        _server.Sent.Clear();
    }

    private IEnumerable<string> Visible(CallerSession caller) => _service.ListVisible(caller).Select(p => p.GroupId);

    private string GroupN => _group.ToString("N");

    [Fact]
    public async Task RegistrationNeedsAParticipantAValidModeAndHappensOnce()
    {
        Assert.Equal(HubStatus.Forbidden, (await _service.RegisterAsync(_peachSession, _group, PartyModes.Public)).Status);
        Assert.Equal(HubStatus.Invalid, (await _service.RegisterAsync(_marioSession, _group, "public")).Status);
        var ok = await _service.RegisterAsync(_marioSession, _group, PartyModes.Public);
        Assert.Equal(HubStatus.Ok, ok.Status);
        Assert.Null(ok.Value!.Code);
        Assert.Equal(HubStatus.Conflict, (await _service.RegisterAsync(_marioSession, _group, PartyModes.Private)).Status);
    }

    [Fact]
    public async Task PublicPartiesAreAnnouncedToEveryoneElse()
    {
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Public);

        var payload = Assert.Single(_server.SentTo("s-luigi"));
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("PartyStarted", json.GetProperty("Type").GetString());
        Assert.Equal(GroupN, json.GetProperty("GroupId").GetString());
        Assert.Equal("Mario · Dune", json.GetProperty("Name").GetString());
        Assert.Equal("Public", json.GetProperty("Mode").GetString());
        Assert.Single(_server.SentTo("s-peach"));
        Assert.Empty(_server.SentTo("s-mario"));
    }

    [Fact]
    public async Task FriendsPartiesAreAnnouncedOnlyToFriendsAndPrivateToNobody()
    {
        await MakeFriends(_mario, _luigi);
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Friends);
        Assert.Equal(new[] { "PartyStarted" }, _server.SentTo("s-luigi").Select(Type));
        Assert.Empty(_server.SentTo("s-peach"));

        var secret = Guid.NewGuid();
        _server.Groups[secret] = ["Mario"];
        _server.Sent.Clear();
        var code = (await _service.RegisterAsync(_marioSession, secret, PartyModes.Private)).Value!.Code;
        Assert.Equal(PartyDirectory.CodeLength, code!.Length);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task TheListFollowsTheModes()
    {
        await MakeFriends(_mario, _luigi);
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Friends);

        Assert.Equal(new[] { GroupN }, Visible(_marioSession));
        Assert.Equal(new[] { GroupN }, Visible(_luigiSession));
        Assert.Empty(Visible(_peachSession));
        var summary = _service.ListVisible(_luigiSession).Single();
        Assert.Equal("Friends", summary.Mode);
        Assert.Equal("Mario · Dune", summary.Name);
        Assert.Equal(new[] { "Mario" }, summary.Participants);
    }

    [Fact]
    public void UnregisteredGroupsShowUpAfterTheGraceAsPublic()
    {
        var other = Guid.NewGuid();
        _server.Groups[other] = ["Bowser"];
        Assert.DoesNotContain(other.ToString("N"), Visible(_peachSession));
        _time.Advance(PartyDirectory.UnregisteredGrace);
        var summary = _service.ListVisible(_peachSession).Single(p => p.GroupId == other.ToString("N"));
        Assert.Equal("Public", summary.Mode);
    }

    [Fact]
    public async Task DetailsOnlyForParticipants()
    {
        var code = (await _service.RegisterAsync(_marioSession, _group, PartyModes.Private)).Value!.Code;
        var details = _service.GetDetails(_marioSession, _group);
        Assert.Equal(HubStatus.Ok, details.Status);
        Assert.Equal(new PartyDetails("Private", code), details.Value);
        Assert.Equal(HubStatus.Forbidden, _service.GetDetails(_peachSession, _group).Status);
    }

    [Fact]
    public async Task TheCodeOpensThePartyAndAttemptsAreLimited()
    {
        var code = (await _service.RegisterAsync(_marioSession, _group, PartyModes.Private)).Value!.Code!;

        Assert.Equal(HubStatus.Forbidden, _service.JoinByCode(_peachSession, "ZZZZZZ").Status);
        var joined = _service.JoinByCode(_peachSession, $"{code[..3].ToLowerInvariant()}-{code[3..]}");
        Assert.Equal(HubStatus.Ok, joined.Status);
        Assert.Equal(GroupN, joined.Value!.GroupId);
        Assert.Equal(new[] { GroupN }, Visible(_peachSession));

        for (var i = 0; i < 3; i++)
        {
            _service.JoinByCode(_peachSession, "ZZZZZZ");
        }

        Assert.Equal(HubStatus.RateLimited, _service.JoinByCode(_peachSession, code).Status);
    }

    [Fact]
    public async Task ACodeOfAnEndedPartyDoesNotWork()
    {
        var code = (await _service.RegisterAsync(_marioSession, _group, PartyModes.Private)).Value!.Code!;
        _server.Groups.Remove(_group);
        Assert.Equal(HubStatus.Forbidden, _service.JoinByCode(_peachSession, code).Status);
        Assert.Equal(1, _service.Cleanup());
    }

    [Fact]
    public async Task InvitesGoOnlyToFriendsOutsideTheParty()
    {
        await MakeFriends(_mario, _luigi);
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Private);
        _server.Sent.Clear();

        Assert.Equal(HubStatus.Forbidden, await _service.InviteAsync(_peachSession, _group, [_luigi.Id.ToString("N")]));
        Assert.Equal(
            HubStatus.Ok,
            await _service.InviteAsync(_marioSession, _group, [_luigi.Id.ToString("N"), _peach.Id.ToString("N"), "nonsense"]));

        var payload = Assert.Single(_server.SentTo("s-luigi"));
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("PartyInvite", json.GetProperty("Type").GetString());
        Assert.Equal("Mario", json.GetProperty("FromName").GetString());
        Assert.Equal("Mario · Dune", json.GetProperty("Name").GetString());
        Assert.Empty(_server.SentTo("s-peach"));
        Assert.Equal(new[] { GroupN }, Visible(_luigiSession));
        Assert.Empty(Visible(_peachSession));
    }

    [Fact]
    public async Task InvitesAreLimitedPerMinute()
    {
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Private);
        var ids = new List<string>();
        for (var i = 0; i < 21; i++)
        {
            var friend = _server.AddUser($"Toad {i:00}");
            await _friends.RequestAsync(friend.Id, _mario.Id);
            await _friends.AcceptAsync(_mario.Id, friend.Id);
            ids.Add(friend.Id.ToString("N"));
        }

        Assert.Equal(HubStatus.RateLimited, await _service.InviteAsync(_marioSession, _group, ids));
    }

    [Fact]
    public async Task PartyOfAFriendIsShownOnlyIfVisible()
    {
        await MakeFriends(_luigi, _peach);
        _server.Groups[_group] = ["Mario", "Luigi"];
        _registry.Register(_group, "s-luigi", "Luigi");
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Friends);

        Assert.Null(_service.PartyOf(_peach.Id, "Peach", _luigi.Id));
        await MakeFriends(_mario, _peach);
        Assert.Equal(new FriendParty(GroupN, "Dune"), _service.PartyOf(_peach.Id, "Peach", _luigi.Id));
        Assert.Null(_service.PartyOf(_peach.Id, "Peach", _mario.Id));
    }
}
