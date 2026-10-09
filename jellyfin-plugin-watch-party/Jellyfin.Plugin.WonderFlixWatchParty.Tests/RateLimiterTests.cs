using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class RateLimiterTests
{
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 2, 21, 0, 0, TimeSpan.Zero));

    private static void Allow(RateLimiter limiter, string type, int times)
    {
        for (var i = 0; i < times; i++)
        {
            Assert.True(limiter.TryAcquire("s1", type), $"{type} n. {i + 1}");
        }
    }

    [Fact]
    public void ChatFivePerTenSeconds()
    {
        var limiter = new RateLimiter(_time);
        Allow(limiter, EventTypes.Chat, 5);
        Assert.False(limiter.TryAcquire("s1", EventTypes.Chat));
        Assert.True(limiter.TryAcquire("s2", EventTypes.Chat), "ogni sessione ha i suoi limiti");
        Assert.True(limiter.TryAcquire("s1", EventTypes.Reaction), "ogni tipo ha i suoi limiti");
        _time.Advance(TimeSpan.FromSeconds(9));
        Assert.False(limiter.TryAcquire("s1", EventTypes.Chat));
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(limiter.TryAcquire("s1", EventTypes.Chat));
    }

    [Fact]
    public void ReactionsEightPerFiveSecondsActionsTwentyPerTen()
    {
        var limiter = new RateLimiter(_time);
        Allow(limiter, EventTypes.Reaction, 8);
        Assert.False(limiter.TryAcquire("s1", EventTypes.Reaction));
        Allow(limiter, EventTypes.Action, 20);
        Assert.False(limiter.TryAcquire("s1", EventTypes.Action));
        _time.Advance(TimeSpan.FromSeconds(5));
        Assert.True(limiter.TryAcquire("s1", EventTypes.Reaction));
        Assert.False(limiter.TryAcquire("s1", EventTypes.Action));
    }

    [Fact]
    public void ForgetClearsASession()
    {
        var limiter = new RateLimiter(_time);
        Allow(limiter, EventTypes.Chat, 5);
        limiter.Forget("s1");
        Assert.True(limiter.TryAcquire("s1", EventTypes.Chat));
    }

    [Fact]
    public void FriendRequestsAreLimitedPerHour()
    {
        var time = new FakeTimeProvider();
        var limiter = new RateLimiter(time);
        for (var i = 0; i < 20; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.FriendRequests));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.FriendRequests));
        Assert.True(limiter.TryAcquire("u2", LimitTypes.FriendRequests));
        time.Advance(TimeSpan.FromHours(1));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.FriendRequests));
    }

    [Fact]
    public void SearchesAreLimitedPerMinute()
    {
        var time = new FakeTimeProvider();
        var limiter = new RateLimiter(time);
        for (var i = 0; i < 30; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.Searches));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.Searches));
        time.Advance(TimeSpan.FromMinutes(1));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.Searches));
    }

    [Fact]
    public void CodeAttemptsAndInvitesArePerMinute()
    {
        var time = new FakeTimeProvider();
        var limiter = new RateLimiter(time);
        for (var i = 0; i < 5; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.CodeAttempts));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.CodeAttempts));
        for (var i = 0; i < 20; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.Invites));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.Invites));
        time.Advance(TimeSpan.FromMinutes(1));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.CodeAttempts));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.Invites));
    }

    [Theory]
    [InlineData(LimitTypes.RecoveryStartMinute, 1, 1)]
    [InlineData(LimitTypes.RecoveryStartHour, 5, 60)]
    [InlineData(LimitTypes.RecoveryStartGlobal, 30, 60)]
    [InlineData(LimitTypes.RecoveryFail, 10, 60)]
    [InlineData(LimitTypes.RecoveryFailGlobal, 100, 60)]
    [InlineData(LimitTypes.LinkStartMinute, 1, 1)]
    [InlineData(LimitTypes.LinkStartHour, 5, 60)]
    public void AccountLimits(string type, int count, int minutes)
    {
        var limiter = new RateLimiter(_time);
        Allow(limiter, type, count);
        Assert.False(limiter.TryAcquire("s1", type));
        Assert.True(limiter.TryAcquire("s2", type), "ogni chiave ha i suoi limiti");
        _time.Advance(TimeSpan.FromMinutes(minutes) - TimeSpan.FromSeconds(1));
        Assert.False(limiter.TryAcquire("s1", type));
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(limiter.TryAcquire("s1", type));
    }

    [Fact]
    public void IsLimitedLooksWithoutCounting()
    {
        var limiter = new RateLimiter(_time);
        for (var i = 0; i < 9; i++)
        {
            Assert.True(limiter.TryAcquire("mario", LimitTypes.RecoveryFail));
        }

        Assert.False(limiter.IsLimited("mario", LimitTypes.RecoveryFail));
        Assert.False(limiter.IsLimited("mario", LimitTypes.RecoveryFail), "guardare non conta");
        Assert.True(limiter.TryAcquire("mario", LimitTypes.RecoveryFail));
        Assert.True(limiter.IsLimited("mario", LimitTypes.RecoveryFail));
        Assert.False(limiter.IsLimited("luigi", LimitTypes.RecoveryFail));
        _time.Advance(TimeSpan.FromHours(1));
        Assert.False(limiter.IsLimited("mario", LimitTypes.RecoveryFail));
        Assert.False(limiter.IsLimited("mario", "TipoSconosciuto"));
    }
}
