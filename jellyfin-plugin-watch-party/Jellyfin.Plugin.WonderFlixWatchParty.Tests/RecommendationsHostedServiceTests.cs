using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecommendationsHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 12, 20, 0, 0, TimeSpan.Zero));

    public void Dispose() => _folder.Dispose();

    [Fact]
    public async Task StartTurnsOnTheLaterRowsAndTheTimerCleansUp()
    {
        var friends = TestRecommendations.Friends(_server, _folder, _time);
        var service = TestRecommendations.Create(_server, _folder, _time, friends);
        var mario = _server.AddUser("Mario");
        var luigi = _server.AddUser("Luigi");
        await TestRecommendations.MakeFriendsAsync(friends, mario.Id, luigi.Id);
        var dune = _server.AddRecommendable("Dune");
        await service.RecommendAsync(mario.Id, new RecommendRequest { ItemId = dune.Id.ToString("N"), To = [luigi.Id.ToString("N")] });
        var layout = new FakeLayout();

        using var hosted = new RecommendationsHostedService(service, layout, _time, NullLogger<RecommendationsHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        Assert.Equal(1, layout.Calls);

        _server.Users.Remove(luigi.Id);
        _time.Advance(RecommendationsHostedService.CleanupInterval);

        var saved = new RecommendationStore(_folder.RecommendationsFile, NullLogger<RecommendationStore>.Instance).Load();
        Assert.Empty(saved.List(luigi.Id));

        await hosted.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task AFailingHomeLayoutDoesNotStopTheStart()
    {
        var friends = TestRecommendations.Friends(_server, _folder, _time);
        var service = TestRecommendations.Create(_server, _folder, _time, friends);

        using var hosted = new RecommendationsHostedService(
            service, new FakeLayout { Fails = true }, _time, NullLogger<RecommendationsHostedService>.Instance);

        await hosted.StartAsync(CancellationToken.None);
        await hosted.StopAsync(CancellationToken.None);
    }

    private sealed class FakeLayout : IHomeLayoutStore
    {
        public int Calls { get; private set; }

        public bool Fails { get; init; }

        public IReadOnlyList<string>? Rows => null;

        public void Save(IReadOnlyList<string>? rows)
        {
        }

        public bool AddLaterRows()
        {
            Calls++;
            return Fails ? throw new InvalidOperationException("configurazione non salvata") : false;
        }
    }
}
