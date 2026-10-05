using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrUserMapTests
{
    private static readonly Guid Mario = Guid.Parse("150fe35a-657b-4c5e-a4fd-644c4c5152b5");
    private static readonly Guid Davide = Guid.Parse("ab8240c5-fc16-49e1-86f6-62fa00ca0fb0");
    private static readonly Guid Stale = Guid.Parse("4135c572-21bd-4677-a3ab-5a7bf3a2fa61");
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTimeProvider _time = new();

    private SeerrUserMap Map() => new(_seerr, _time, NullLogger<SeerrUserMap>.Instance);

    [Fact]
    public async Task MatchesByJellyfinIdInAnyFormatAndTheLowestSeerrIdWins()
    {
        _seerr.Users.Add(new SeerrUser { Id = 9, Permissions = 32, JellyfinUserId = "ab8240c5fc1649e186f662fa00ca0fb0" });
        _seerr.Users.Add(new SeerrUser { Id = 3, Permissions = 34, JellyfinUserId = "AB8240C5-FC16-49E1-86F6-62FA00CA0FB0" });
        _seerr.Users.Add(new SeerrUser { Id = 1, Permissions = 2, JellyfinUserId = Stale.ToString("N") });
        var map = Map();

        Assert.Equal(3, (await map.FindAsync(Davide, Ct))!.Id);
        Assert.Null(await map.FindAsync(Mario, Ct));
    }

    [Fact]
    public async Task UsersStayInMemoryForTenMinutes()
    {
        var map = Map();
        await map.FindAsync(Mario, Ct);
        await map.FindAsync(Davide, Ct);
        Assert.Single(_seerr.Calls, "GetUsers");

        _time.Advance(SeerrUserMap.CacheFor);
        await map.FindAsync(Mario, Ct);

        Assert.Equal(2, _seerr.Calls.Count(c => c == "GetUsers"));
    }

    [Fact]
    public async Task EnsureImportsAMissingAccountOnce()
    {
        _seerr.OnImport = id => new SeerrUser { Id = 30, Permissions = 32, JellyfinUserId = id.ToString("N") };
        var map = Map();

        Assert.Equal(30, (await map.EnsureAsync(Mario, Ct)).Id);
        Assert.Equal(new[] { "GetUsers", "Import", "GetUsers" }, _seerr.Calls);
        Assert.Equal(30, (await map.EnsureAsync(Mario, Ct)).Id);
        Assert.Single(_seerr.Calls, "Import");
    }

    [Fact]
    public async Task AnImportThatCreatesNobodyOrIsRefusedMeansAccountUnavailable()
    {
        var map = Map();
        async Task<SeerrError> ErrorOf() =>
            (await Assert.ThrowsAsync<SeerrException>(() => map.EnsureAsync(Mario, Ct))).Error;

        Assert.Equal(SeerrError.AccountUnavailable, await ErrorOf());

        _seerr.FailOn["Import"] = SeerrError.NoPermission;
        Assert.Equal(SeerrError.AccountUnavailable, await ErrorOf());

        // Seerr giù non è un problema dell'account: passa com'è.
        _seerr.FailOn["Import"] = SeerrError.Unavailable;
        Assert.Equal(SeerrError.Unavailable, await ErrorOf());
    }

    [Fact]
    public async Task ManagersAreAdminsAndRequestManagersWithAJellyfinId()
    {
        _seerr.Users.Add(new SeerrUser { Id = 1, Permissions = 2, JellyfinUserId = Stale.ToString("N") });
        _seerr.Users.Add(new SeerrUser { Id = 3, Permissions = 34, JellyfinUserId = Davide.ToString("N") });
        _seerr.Users.Add(new SeerrUser { Id = 4, Permissions = 16, JellyfinUserId = null });
        _seerr.Users.Add(new SeerrUser { Id = 5, Permissions = 32, JellyfinUserId = Mario.ToString("N") });

        Assert.Equal(new[] { Stale, Davide }, await Map().ManagerJellyfinIdsAsync(Ct));
    }

    [Fact]
    public async Task DefaultPermissionsAreReadOnceInTenMinutes()
    {
        _seerr.DefaultPermissions = 32;
        var map = Map();

        Assert.Equal(32, await map.DefaultPermissionsAsync(Ct));
        Assert.Equal(32, await map.DefaultPermissionsAsync(Ct));

        Assert.Single(_seerr.Calls, "GetMainSettings");
    }
}
