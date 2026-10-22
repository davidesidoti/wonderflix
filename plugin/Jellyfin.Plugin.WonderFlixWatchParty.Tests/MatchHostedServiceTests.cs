using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class MatchHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 14, 20, 0, 0, TimeSpan.Zero));
    private readonly MatchService _match;
    private readonly UserRef _mario;

    public MatchHostedServiceTests()
    {
        _mario = _server.AddUser("Mario");
        _server.AddSession("s-mario", _mario);
        _match = TestMatch.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time));
    }

    public void Dispose()
    {
        _match.Dispose();
        _folder.Dispose();
    }

    [Fact]
    public async Task CleanupRunsEveryThirtySeconds()
    {
        using var hosted = new MatchHostedService(_match, _time, NullLogger<MatchHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        _server.Sessions.Clear();

        // 30 s: si segna l'assenza; 60 s dopo chi ha aperto è fuori e la sala si chiude.
        for (var i = 0; i < 3; i++)
        {
            _time.Advance(MatchHostedService.CleanupInterval);
        }

        Assert.Equal(MatchClosedReasons.CreatorLeft, _match.Get(_mario.Id, room).State!.ClosedReason);
        await hosted.StopAsync(CancellationToken.None);
    }
}
