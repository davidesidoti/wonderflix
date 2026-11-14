using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SeerrRequestListTests
{
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 14, 12, 0, 0, TimeSpan.Zero));
    private readonly SeerrRequestList _list;

    public SeerrRequestListTests() => _list = new SeerrRequestList(_seerr, _time);

    private void Fill(int count) =>
        _seerr.Requests.AddRange(Enumerable.Range(1, count).Select(i => new SeerrRequest { Id = i }));

    private int Reads => _seerr.Calls.Count(c => c == "GetRequests");

    [Fact]
    public async Task ReadsEveryPageAdvancingByTheResultsReceived()
    {
        Fill(250);
        Assert.Equal(250, (await _list.GetAsync(3, null, default)).Count);
        Assert.Equal([0, 100, 200], _seerr.Listed.Select(l => l.Skip));
        Assert.All(_seerr.Listed, l => Assert.Equal("all", l.Filter));
    }

    [Fact]
    public async Task AdvancesBySmallerPagesToo()
    {
        Fill(100);
        _seerr.MaxPerPage = 40;
        Assert.Equal(100, (await _list.GetAsync(3, null, default)).Count);
        Assert.Equal([0, 40, 80], _seerr.Listed.Select(l => l.Skip));
    }

    [Fact]
    public async Task SecondCallWithin30SecondsDoesNotReadAgain()
    {
        Fill(3);
        await _list.GetAsync(3, null, default);
        _time.Advance(TimeSpan.FromSeconds(29));
        await _list.GetAsync(3, null, default);
        Assert.Equal(1, Reads);

        _time.Advance(TimeSpan.FromSeconds(2));
        await _list.GetAsync(3, null, default);
        Assert.Equal(2, Reads);
    }

    [Fact]
    public async Task ScopesAreSeparate()
    {
        Fill(3);
        await _list.GetAsync(3, null, default);
        await _list.GetAsync(24, 24, default);
        Assert.Equal(2, Reads);
        Assert.Equal([null, 24], _seerr.Listed.Select(l => l.RequestedBy));
    }

    [Fact]
    public async Task ConcurrentCallsShareOneRead()
    {
        Fill(3);
        var gate = new TaskCompletionSource();
        _seerr.RequestsGate = gate.Task;
        var a = _list.GetAsync(3, null, default);
        var b = _list.GetAsync(3, null, default);
        gate.SetResult();
        Assert.Equal(3, (await a).Count);
        Assert.Equal(3, (await b).Count);
        Assert.Equal(1, Reads);
    }

    [Fact]
    public async Task ClearForcesANewRead()
    {
        Fill(3);
        await _list.GetAsync(3, null, default);
        _list.Clear();
        await _list.GetAsync(3, null, default);
        Assert.Equal(2, Reads);
    }

    [Fact]
    public async Task AFailedReadIsNotCached()
    {
        Fill(3);
        _seerr.FailWith = SeerrError.Unavailable;
        await Assert.ThrowsAsync<SeerrException>(() => _list.GetAsync(3, null, default));

        _seerr.FailWith = null;
        Assert.Equal(3, (await _list.GetAsync(3, null, default)).Count);
        Assert.Equal(2, Reads);
    }
}
