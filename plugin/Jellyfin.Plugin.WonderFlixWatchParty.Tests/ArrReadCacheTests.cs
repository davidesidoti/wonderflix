using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ArrReadCacheTests
{
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 10, 14, 30, 0, TimeSpan.Zero));
    private readonly RecordingLogger<ArrReadCacheTests> _logger = new();
    private int _reads;

    private ArrReadCache<int> Cache(int max = 10) => new(_time, max, _logger);

    private Task<int> Count()
    {
        _reads++;
        return Task.FromResult(_reads);
    }

    [Fact]
    public async Task AReadIsKeptForFifteenMinutes()
    {
        var cache = Cache();
        await cache.GetAsync("a", Count);
        var second = await cache.GetAsync("a", Count);
        Assert.Equal(1, _reads);
        Assert.Equal(1, second.Value);
        Assert.Null(second.Error);

        _time.Advance(TimeSpan.FromMinutes(15));
        await cache.GetAsync("a", Count);
        Assert.Equal(2, _reads);
    }

    [Fact]
    public async Task AnErrorIsKeptForAMinute()
    {
        var cache = Cache();
        Task<int> Fail()
        {
            _reads++;
            throw new ArrException(ArrError.Unauthorized);
        }

        var first = await cache.GetAsync("a", Fail);
        Assert.Equal("Unauthorized", first.Error);

        _time.Advance(TimeSpan.FromSeconds(59));
        await cache.GetAsync("a", Fail);
        Assert.Equal(1, _reads);

        _time.Advance(TimeSpan.FromSeconds(1));
        await cache.GetAsync("a", Fail);
        Assert.Equal(2, _reads);
    }

    [Fact]
    public async Task AnUnexpectedFailureIsUnreachableAndLogged()
    {
        var result = await Cache().GetAsync("a", () => throw new InvalidOperationException("boom"));
        Assert.Equal("Unreachable", result.Error);
        Assert.Single(_logger.Entries, e => e.Level == LogLevel.Warning);
    }

    [Fact]
    public async Task CallersAskingTogetherShareOneRead()
    {
        var gate = new TaskCompletionSource<int>();
        var cache = Cache();
        Task<int> Slow()
        {
            _reads++;
            return gate.Task;
        }

        var first = cache.GetAsync("a", Slow);
        var second = cache.GetAsync("a", Slow);
        gate.SetResult(7);
        Assert.Equal(7, (await first).Value);
        Assert.Equal(7, (await second).Value);
        Assert.Equal(1, _reads);
    }

    [Fact]
    public async Task KeysAreSeparate()
    {
        var cache = Cache();
        await cache.GetAsync("a", Count);
        await cache.GetAsync("b", Count);
        Assert.Equal(2, _reads);
    }

    [Fact]
    public async Task TheOldestEntryGoesWhenFull()
    {
        var cache = Cache(2);
        await cache.GetAsync("a", Count);
        await cache.GetAsync("b", Count);
        await cache.GetAsync("c", Count);
        Assert.Equal(3, _reads);

        await cache.GetAsync("c", Count);
        Assert.Equal(3, _reads);

        await cache.GetAsync("a", Count);
        Assert.Equal(4, _reads);
    }
}
