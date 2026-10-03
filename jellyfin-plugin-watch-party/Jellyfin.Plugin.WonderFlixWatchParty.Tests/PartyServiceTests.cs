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
    private readonly PartyAnnouncer _announcer;
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
        var parties = new PartyDirectory(_time);
        _announcer = new PartyAnnouncer(
            parties, _server, _server, _friends, _server, _time, NullLogger<PartyAnnouncer>.Instance);
        _service = new PartyService(
            parties, _server, _server, _server, _friends, _registry, _announcer, _server,
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

    public void Dispose()
    {
        _announcer.Dispose();
        _folder.Dispose();
    }

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
    public void RegistrationNeedsAParticipantAValidModeAndHappensOnce()
    {
        Assert.Equal(HubStatus.Forbidden, _service.Register(_peachSession, _group, PartyModes.Public).Status);
        Assert.Equal(HubStatus.Invalid, _service.Register(_marioSession, _group, "public").Status);
        var ok = _service.Register(_marioSession, _group, PartyModes.Public);
        Assert.Equal(HubStatus.Ok, ok.Status);
        Assert.Null(ok.Value!.Code);
        Assert.Equal(HubStatus.Conflict, _service.Register(_marioSession, _group, PartyModes.Private).Status);
    }

    [Fact]
    public void OnlyTheCreatorAloneCanRegisterTheGroup()
    {
        // Un gruppo con altri dentro (es. di jellyfin-web) non si registra: non si nasconde il gruppo di un altro.
        _server.Groups[_group] = ["Mario", "Luigi"];
        Assert.Equal(HubStatus.Forbidden, _service.Register(_marioSession, _group, PartyModes.Private).Status);
        Assert.Equal(HubStatus.Forbidden, _service.Register(_luigiSession, _group, PartyModes.Private).Status);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public void PublicPartiesAreAnnouncedToEveryoneElseOnceTheQueueIsSet()
    {
        _service.Register(_marioSession, _group, PartyModes.Public);
        Assert.Empty(_server.Sent);
        _server.GroupStates[_group] = "Waiting";
        _time.Advance(PartyAnnouncer.Delay);

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
        _service.Register(_marioSession, _group, PartyModes.Friends);
        _server.GroupStates[_group] = "Waiting";
        _time.Advance(PartyAnnouncer.Delay);
        Assert.Equal(new[] { "PartyStarted" }, _server.SentTo("s-luigi").Select(Type));
        Assert.Empty(_server.SentTo("s-peach"));

        var secret = Guid.NewGuid();
        _server.Groups[secret] = ["Mario"];
        _server.GroupStates[secret] = "Waiting";
        _server.Sent.Clear();
        var code = _service.Register(_marioSession, secret, PartyModes.Private).Value!.Code;
        Assert.Equal(PartyDirectory.CodeLength, code!.Length);
        _time.Advance(PartyAnnouncer.GiveUpAfter);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task TheListFollowsTheModes()
    {
        await MakeFriends(_mario, _luigi);
        _service.Register(_marioSession, _group, PartyModes.Friends);

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
    public void DetailsOnlyForParticipants()
    {
        var code = _service.Register(_marioSession, _group, PartyModes.Private).Value!.Code;
        var details = _service.GetDetails(_marioSession, _group);
        Assert.Equal(HubStatus.Ok, details.Status);
        Assert.Equal(new PartyDetails("Private", code), details.Value);
        Assert.Equal(HubStatus.Forbidden, _service.GetDetails(_peachSession, _group).Status);
    }

    [Fact]
    public void TheCodeOpensThePartyAndAttemptsAreLimited()
    {
        var code = _service.Register(_marioSession, _group, PartyModes.Private).Value!.Code!;

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
    public void ACodeOfAnEndedPartyDoesNotWork()
    {
        var code = _service.Register(_marioSession, _group, PartyModes.Private).Value!.Code!;
        _server.Groups.Remove(_group);
        Assert.Equal(HubStatus.Forbidden, _service.JoinByCode(_peachSession, code).Status);
        Assert.Equal(1, _service.Cleanup());
    }

    [Fact]
    public async Task InvitesGoOnlyToFriendsOutsideTheParty()
    {
        await MakeFriends(_mario, _luigi);
        _service.Register(_marioSession, _group, PartyModes.Private);
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
    public async Task InvitesReachOnlySessionsThatCanSeeTheGroup()
    {
        await MakeFriends(_mario, _luigi);
        await MakeFriends(_mario, _peach);
        _service.Register(_marioSession, _group, PartyModes.Private);
        // Luigi non ha accesso alla libreria del titolo in coda: dalla sua sessione il gruppo non si vede.
        _server.Hidden.Add(("s-luigi", _group));

        Assert.Equal(
            HubStatus.Ok,
            await _service.InviteAsync(_marioSession, _group, [_luigi.Id.ToString("N"), _peach.Id.ToString("N")]));

        Assert.Empty(_server.SentTo("s-luigi"));
        Assert.Equal(new[] { "PartyInvite" }, _server.SentTo("s-peach").Select(Type));
    }

    [Fact]
    public async Task InvitesAreLimitedPerMinute()
    {
        _service.Register(_marioSession, _group, PartyModes.Private);
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
    public void PartyOfIgnoresAStaleRegistryEntry()
    {
        // Luigi risulta ancora nel canale (Leave fallita) ma non è più tra i partecipanti del gruppo.
        _service.Register(_marioSession, _group, PartyModes.Public);
        _registry.Register(_group, "s-luigi", "Luigi");

        Assert.Null(_service.PartyOf(_peachSession, _luigi.Id));
    }

    [Fact]
    public async Task PartyOfAFriendIsShownOnlyIfVisible()
    {
        await MakeFriends(_luigi, _peach);
        // Il party si registra quando c'è solo il creatore; Luigi entra dopo.
        _service.Register(_marioSession, _group, PartyModes.Friends);
        _server.Groups[_group] = ["Mario", "Luigi"];
        _registry.Register(_group, "s-luigi", "Luigi");

        Assert.Null(_service.PartyOf(_peachSession, _luigi.Id));
        await MakeFriends(_mario, _peach);
        Assert.Equal(new FriendParty(GroupN, "Dune"), _service.PartyOf(_peachSession, _luigi.Id));
        Assert.Null(_service.PartyOf(_peachSession, _mario.Id));
    }

    [Fact]
    public void PartyOfNeedsTheViewersSessionToSeeTheGroup()
    {
        _service.Register(_marioSession, _group, PartyModes.Public);
        _server.Groups[_group] = ["Mario", "Luigi"];
        _registry.Register(_group, "s-luigi", "Luigi");
        Assert.Equal(new FriendParty(GroupN, "Dune"), _service.PartyOf(_peachSession, _luigi.Id));

        // Senza accesso alla libreria del titolo Peach non vede il gruppo: niente titolo, niente Unisciti.
        _server.Hidden.Add(("s-peach", _group));
        Assert.Null(_service.PartyOf(_peachSession, _luigi.Id));

        // Una sessione che non c'è più non vede nessun gruppo.
        Assert.Null(_service.PartyOf(new CallerSession("s-finita", _peach.Id, "Peach"), _luigi.Id));
    }
}
