using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RatingsHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 20, 21, 0, 0, TimeSpan.Zero));
    private readonly Guid _group = Guid.NewGuid();
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly RatedTitle _film;
    private readonly RatingService _ratings;
    private readonly RatingRoundService _rounds;

    public RatingsHostedServiceTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _server.AddSession("s-mario", _mario);
        _server.Groups[_group] = ["Mario"];
        _film = _server.AddRated("Il Padrino (1972)");
        _server.RoundTargets[_film.Id] = _film.Id;
        var parties = new PartyDirectory(_time);
        parties.Register(_group, _mario.Id, PartyModes.Friends);
        _ratings = TestRatings.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time));
        _rounds = TestRatings.Rounds(_server, _ratings, _time, parties);
    }

    public void Dispose()
    {
        _rounds.Dispose();
        _folder.Dispose();
    }

    [Fact]
    public async Task StartLoadsAndBothTimersClean()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.RatingsFile)!);
        File.WriteAllText(_folder.RatingsFile, "{nope");
        using var hosted = new RatingsHostedService(_ratings, _rounds, _time, NullLogger<RatingsHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        Assert.True(File.Exists(_folder.RatingsFile + ".bad"));

        // La votazione scoperta viene scartata 10 minuti dopo, dal giro dei 30 s.
        _rounds.Open(_mario.Id, new OpenRatingRoundRequest { GroupId = _group.ToString("N"), ItemId = _film.Id.ToString("N") });
        _rounds.Reveal(_mario.Id, _group);
        Assert.NotNull(_rounds.Get(_mario.Id, _group).State);
        _time.Advance(RatingRoundService.RevealedKept);
        Assert.Null(_rounds.Get(_mario.Id, _group).State);

        // Un utente tolto: il suo voto sparisce dal file al giro dei 5 minuti.
        _ratings.Save(_luigi.Id, _film.Id, 8, null);
        Assert.Contains(_luigi.Id.ToString("N"), File.ReadAllText(_folder.RatingsFile));
        _server.Users.Remove(_luigi.Id);
        _time.Advance(RatingsHostedService.StoreInterval);
        Assert.DoesNotContain(_luigi.Id.ToString("N"), File.ReadAllText(_folder.RatingsFile));
        await hosted.StopAsync(CancellationToken.None);
    }
}
