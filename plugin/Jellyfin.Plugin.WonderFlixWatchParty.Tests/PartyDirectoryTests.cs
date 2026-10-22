using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PartyDirectoryTests
{
    private readonly FakeTimeProvider _time = new();
    private readonly PartyDirectory _parties;
    private readonly Guid _group = Guid.NewGuid();
    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();

    public PartyDirectoryTests() => _parties = new PartyDirectory(_time);

    [Fact]
    public void RegistersOnceAndOnlyPrivatePartiesHaveACode()
    {
        var view = _parties.Register(_group, _mario, PartyModes.Public)!;
        Assert.Null(view.Code);
        Assert.Equal(_mario, view.CreatorId);
        Assert.Null(_parties.Register(_group, _luigi, PartyModes.Private));
        Assert.Equal(PartyModes.Public, _parties.Get(_group)!.Mode);

        var other = Guid.NewGuid();
        var code = _parties.Register(other, _mario, PartyModes.Private)!.Code!;
        Assert.Equal(PartyDirectory.CodeLength, code.Length);
        Assert.All(code, c => Assert.Contains(c, PartyDirectory.CodeAlphabet));
        Assert.Equal(other, _parties.FindByCode(code));
        // Minuscole, trattino e spazi non contano.
        Assert.Equal(other, _parties.FindByCode($" {code[..3].ToLowerInvariant()}-{code[3..]} "));
        Assert.Null(_parties.FindByCode("ZZZ-ZZZ"));
        Assert.Null(_parties.FindByCode("troppo-lungo"));
        Assert.Null(_parties.FindByCode(null));
    }

    [Fact]
    public void CodesAreUnique()
    {
        var codes = Enumerable.Range(0, 300)
            .Select(_ => _parties.Register(Guid.NewGuid(), _mario, PartyModes.Private)!.Code)
            .ToList();
        Assert.Equal(codes.Count, codes.Distinct().Count());
    }

    [Fact]
    public void VisibilityFollowsTheMode()
    {
        var friends = Guid.NewGuid();
        var secret = Guid.NewGuid();
        _parties.Register(_group, _mario, PartyModes.Public);
        _parties.Register(friends, _mario, PartyModes.Friends);
        _parties.Register(secret, _mario, PartyModes.Private);
        bool FriendOfMario(Guid creator) => creator == _mario;
        bool Nobody(Guid creator) => false;

        Assert.True(_parties.IsVisible(_group, _luigi, Nobody));
        Assert.True(_parties.IsVisible(friends, _luigi, FriendOfMario));
        Assert.False(_parties.IsVisible(friends, _luigi, Nobody));
        Assert.False(_parties.IsVisible(secret, _luigi, FriendOfMario));
        // Il creatore lo vede sempre; chi è invitato (o entra col codice) anche.
        Assert.True(_parties.IsVisible(secret, _mario, Nobody));
        _parties.Grant(secret, [_luigi]);
        Assert.True(_parties.IsVisible(secret, _luigi, Nobody));
    }

    [Fact]
    public void UnregisteredGroupsBecomePublicAfterTheGrace()
    {
        Assert.False(_parties.IsVisible(_group, _luigi, _ => false));
        _parties.Seen(_group);
        _time.Advance(PartyDirectory.UnregisteredGrace - TimeSpan.FromSeconds(1));
        _parties.Seen(_group);
        Assert.False(_parties.IsVisible(_group, _luigi, _ => false));
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(_parties.IsVisible(_group, _luigi, _ => false));
    }

    [Fact]
    public void ForgetRemovesEndedPartiesAndTheirCodes()
    {
        var code = _parties.Register(_group, _mario, PartyModes.Private)!.Code;
        var alive = Guid.NewGuid();
        _parties.Register(alive, _mario, PartyModes.Public);
        _parties.Seen(Guid.NewGuid());

        Assert.Equal(1, _parties.Forget(id => id == alive));

        Assert.Null(_parties.Get(_group));
        Assert.Null(_parties.FindByCode(code));
        Assert.NotNull(_parties.Get(alive));
    }

    [Fact]
    public void AForgottenPartyIsNeverUnregisteredAgain()
    {
        // Il gruppo sembrava finito (coda illeggibile, o dentro solo jellyfin-web) ma c'è ancora.
        _parties.Register(_group, _mario, PartyModes.Private);
        Assert.Equal(1, _parties.Forget(_ => false));

        _parties.Seen(_group);
        _time.Advance(PartyDirectory.UnregisteredGrace);
        Assert.False(_parties.IsVisible(_group, _luigi, _ => true));
        Assert.False(_parties.IsVisible(_group, _mario, _ => true));
        Assert.Null(_parties.Get(_group));
        // Né si registra di nuovo.
        Assert.Null(_parties.Register(_group, _mario, PartyModes.Public));

        // Un gruppo mai registrato invece torna come prima.
        var unregistered = Guid.NewGuid();
        _parties.Seen(unregistered);
        _parties.Forget(_ => false);
        _parties.Seen(unregistered);
        _time.Advance(PartyDirectory.UnregisteredGrace);
        Assert.True(_parties.IsVisible(unregistered, _luigi, _ => false));
    }

    [Fact]
    public void ForgottenPartiesAreRememberedForALimitedTime()
    {
        _parties.Register(_group, _mario, PartyModes.Private);
        _parties.Forget(_ => false);
        _parties.Seen(_group);

        _time.Advance(PartyDirectory.TombstoneLifetime - TimeSpan.FromSeconds(1));
        _parties.Forget(_ => true);
        Assert.False(_parties.IsVisible(_group, _luigi, _ => false));

        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(_parties.IsVisible(_group, _luigi, _ => false));
        _parties.Forget(_ => true);
        Assert.True(_parties.IsVisible(_group, _luigi, _ => false));
    }

    [Fact]
    public void ForgottenPartiesAreRememberedUpToALimit()
    {
        _parties.Register(_group, _mario, PartyModes.Private);
        _parties.Forget(_ => false);
        _time.Advance(TimeSpan.FromSeconds(1));
        var others = Enumerable.Range(0, PartyDirectory.MaxTombstones).Select(_ => Guid.NewGuid()).ToList();
        foreach (var id in others)
        {
            _parties.Register(id, _mario, PartyModes.Private);
        }

        Assert.Equal(PartyDirectory.MaxTombstones, _parties.Forget(_ => false));

        // Il più vecchio lascia il posto: il suo gruppo torna come uno mai registrato.
        _parties.Seen(_group);
        _parties.Seen(others[0]);
        _time.Advance(PartyDirectory.UnregisteredGrace);
        Assert.True(_parties.IsVisible(_group, _luigi, _ => false));
        Assert.False(_parties.IsVisible(others[0], _luigi, _ => false));
    }
}
