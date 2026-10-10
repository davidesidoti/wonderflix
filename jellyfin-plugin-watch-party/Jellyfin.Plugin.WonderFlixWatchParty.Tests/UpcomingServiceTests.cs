using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UpcomingServiceTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 10, 14, 30, 0, TimeSpan.Zero);

    private readonly FakeTimeProvider _time = new(Now);
    private readonly FakeArrClient _client = new();
    private readonly FakeArrSettings _settings = new();
    private readonly FakeSeriesIndex _index = new();
    private readonly FakeServer _server = new();
    private readonly RecordingLogger<UpcomingService> _logger = new();

    private UpcomingService Service() => new(_client, _settings, _index, _server, _time, _logger);

    private static SonarrEpisode Episode(DateTimeOffset at) => new()
    {
        SeriesId = 1,
        SeasonNumber = 2,
        EpisodeNumber = 5,
        Title = "Cinque",
        AirDateUtc = at,
        Series = new SonarrSeries
        {
            Title = "The Bear",
            TvdbId = 136311,
            TmdbId = 136315,
            ImdbId = "tt14452776",
            Images =
            [
                new ArrImage { CoverType = "poster", RemoteUrl = "https://artworks.thetvdb.com/p.jpg" },
                new ArrImage { CoverType = "fanart", RemoteUrl = "https://artworks.thetvdb.com/f.jpg" },
            ],
        },
    };

    private void EpisodesAre(params SonarrEpisode?[] episodes) =>
        _client.Episodes = (_, _) => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(episodes);

    [Fact]
    public async Task NotConfiguredAnswersWithoutCallingSonarrOrRadarr()
    {
        _settings.Sonarr = ArrEndpoint.None;
        _settings.Radarr = ArrEndpoint.None;
        var service = Service();

        var series = await service.GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);
        var movies = await service.GetMoviesAsync(CancellationToken.None);

        Assert.Empty(series.Items);
        Assert.Equal("NotConfigured", series.Error);
        Assert.Empty(movies.Items);
        Assert.Equal("NotConfigured", movies.Error);
        Assert.Empty(_client.EpisodeCalls);
        Assert.Empty(_client.MovieCalls);
    }

    [Fact]
    public async Task SeriesAskFromTwelveHoursAgoToTheConfiguredDays()
    {
        _settings.SeriesDays = 10;

        await Service().GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);

        var (from, to) = Assert.Single(_client.EpisodeCalls);
        Assert.Equal(Now.AddHours(-12), from);
        Assert.Equal(Now.AddDays(10), to);
    }

    [Fact]
    public async Task MoviesAskFromTodayToTheEndOfTheLastDay()
    {
        await Service().GetMoviesAsync(CancellationToken.None);

        var (from, to) = Assert.Single(_client.MovieCalls);
        Assert.Equal(new DateTimeOffset(2026, 10, 10, 0, 0, 0, TimeSpan.Zero), from);
        // 90 giorni compreso l'ultimo: fino alla mezzanotte del 9 gennaio.
        Assert.Equal(new DateTimeOffset(2027, 1, 9, 0, 0, 0, TimeSpan.Zero), to);
    }

    [Fact]
    public async Task EachUserGetsTheSeriesIdOnlyWhenTheySeeIt()
    {
        var mario = _server.AddUser("mario");
        var luigi = _server.AddUser("luigi");
        var hidden = Guid.NewGuid();
        var visible = Guid.NewGuid();
        _index.Series.Add(new LibrarySeries(hidden, "136311", null, null));
        _index.Series.Add(new LibrarySeries(visible, null, "136315", null));
        _server.Unseen.Add((mario.Id, hidden));
        _server.Unseen.Add((luigi.Id, hidden));
        _server.Unseen.Add((luigi.Id, visible));
        EpisodesAre(Episode(Now.AddDays(1)));
        var service = Service();

        var forMario = Assert.Single((await service.GetSeriesAsync(mario.Id, CancellationToken.None)).Items);
        var forLuigi = Assert.Single((await service.GetSeriesAsync(luigi.Id, CancellationToken.None)).Items);
        var forApiKey = Assert.Single((await service.GetSeriesAsync(Guid.Empty, CancellationToken.None)).Items);

        Assert.Equal(visible.ToString("N"), forMario.JellyfinSeriesId);
        Assert.Null(forLuigi.JellyfinSeriesId);
        Assert.Null(forApiKey.JellyfinSeriesId);
        Assert.Equal("The Bear", forMario.SeriesName);
        Assert.Equal(2, forMario.SeasonNumber);
        Assert.Equal(5, forMario.EpisodeNumber);
        Assert.Null(forMario.LastEpisodeNumber);
        Assert.Equal("Cinque", forMario.EpisodeTitle);
        Assert.Equal(Now.AddDays(1), forMario.AirDateUtc);
        Assert.Equal(136311, forMario.TvdbId);
        Assert.Equal(136315, forMario.TmdbId);
        Assert.Equal("https://artworks.thetvdb.com/p.jpg", forMario.PosterUrl);
        Assert.Equal("https://artworks.thetvdb.com/f.jpg", forMario.BackdropUrl);
        // Una sola lettura di Sonarr per tre utenti.
        Assert.Single(_client.EpisodeCalls);
    }

    [Fact]
    public async Task TheLibraryFailingLeavesTheEpisodesWithoutTheSeries()
    {
        var mario = _server.AddUser("mario");
        _index.Series.Add(new LibrarySeries(Guid.NewGuid(), "136311", null, null));
        EpisodesAre(Episode(Now.AddDays(1)));
        _server.LibraryFails = true;

        var item = Assert.Single((await Service().GetSeriesAsync(mario.Id, CancellationToken.None)).Items);
        Assert.Null(item.JellyfinSeriesId);

        // Un servizio nuovo (cache vuota) con l'elenco delle serie che non si legge.
        _server.LibraryFails = false;
        _index.Fails = true;
        var again = Assert.Single((await Service().GetSeriesAsync(mario.Id, CancellationToken.None)).Items);
        Assert.Null(again.JellyfinSeriesId);
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Warning);
    }

    [Fact]
    public async Task AnswersStayCachedForFifteenMinutes()
    {
        EpisodesAre(Episode(Now.AddDays(1)));
        var service = Service();

        await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        _time.Advance(TimeSpan.FromMinutes(15) - TimeSpan.FromSeconds(1));
        await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        Assert.Single(_client.EpisodeCalls);

        _time.Advance(TimeSpan.FromSeconds(2));
        await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        Assert.Equal(2, _client.EpisodeCalls.Count);
    }

    [Fact]
    public async Task ChangedSettingsDoNotUseTheOldCache()
    {
        _client.Episodes = (_, _) => throw new ArrException(ArrError.Unreachable);
        var service = Service();

        Assert.Equal("Unreachable", (await service.GetSeriesAsync(Guid.Empty, CancellationToken.None)).Error);

        // L'admin corregge l'indirizzo: la richiesta dopo non aspetta che l'errore scada.
        EpisodesAre(Episode(Now.AddDays(1)));
        _settings.Sonarr = _settings.Sonarr with { Url = "https://arr.example/sonarr-giusto" };
        var fixedAnswer = await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        Assert.Null(fixedAnswer.Error);
        Assert.Single(fixedAnswer.Items);

        _settings.SeriesDays = 14;
        await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        Assert.Equal(3, _client.EpisodeCalls.Count);
    }

    [Fact]
    public async Task ErrorsAreKeptForAMinute()
    {
        _client.Movies = (_, _) => throw new ArrException(ArrError.Unauthorized);
        var service = Service();

        var refused = await service.GetMoviesAsync(CancellationToken.None);
        Assert.Empty(refused.Items);
        Assert.Equal("Unauthorized", refused.Error);

        _time.Advance(TimeSpan.FromSeconds(59));
        await service.GetMoviesAsync(CancellationToken.None);
        Assert.Single(_client.MovieCalls);

        _time.Advance(TimeSpan.FromSeconds(2));
        _client.Movies = (_, _) => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);
        Assert.Null((await service.GetMoviesAsync(CancellationToken.None)).Error);
        Assert.Equal(2, _client.MovieCalls.Count);
    }

    [Fact]
    public async Task AnUnexpectedFailureIsUnreachableAndRetriedAfterAMinute()
    {
        _client.Episodes = (_, _) => throw new InvalidOperationException("guasto");
        var service = Service();

        Assert.Equal("Unreachable", (await service.GetSeriesAsync(Guid.Empty, CancellationToken.None)).Error);
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Warning && e.Exception is InvalidOperationException);

        _time.Advance(TimeSpan.FromSeconds(61));
        EpisodesAre(Episode(Now.AddDays(1)));
        Assert.Null((await service.GetSeriesAsync(Guid.Empty, CancellationToken.None)).Error);
        Assert.Equal(2, _client.EpisodeCalls.Count);
    }

    [Fact]
    public async Task UsersAskingTogetherShareOneRead()
    {
        var gate = new TaskCompletionSource<IReadOnlyList<SonarrEpisode?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        _client.Episodes = (_, _) => gate.Task;
        var service = Service();

        var first = service.GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);
        var second = service.GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);
        gate.SetResult([Episode(Now.AddDays(1))]);

        Assert.Single((await first).Items);
        Assert.Single((await second).Items);
        Assert.Single(_client.EpisodeCalls);
    }

    [Fact]
    public async Task ACancelledCallerDoesNotStopTheReadForTheOthers()
    {
        var gate = new TaskCompletionSource<IReadOnlyList<SonarrEpisode?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        _client.Episodes = (_, _) => gate.Task;
        var service = Service();
        using var cancel = new CancellationTokenSource();

        var leaving = service.GetSeriesAsync(Guid.NewGuid(), cancel.Token);
        var staying = service.GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);
        await cancel.CancelAsync();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => leaving);

        gate.SetResult([Episode(Now.AddDays(1))]);
        Assert.Single((await staying).Items);
        Assert.Single(_client.EpisodeCalls);
    }

    [Fact]
    public async Task MoviesBecomeDtos()
    {
        _client.Movies = (_, _) => Task.FromResult<IReadOnlyList<RadarrMovie?>>(
        [
            new RadarrMovie
            {
                Title = "Hope",
                Year = 2026,
                TmdbId = 1058424,
                DigitalRelease = new DateTimeOffset(2026, 10, 13, 0, 0, 0, TimeSpan.Zero),
                Images = [new ArrImage { CoverType = "poster", RemoteUrl = "https://image.tmdb.org/t/p/original/p.jpg" }],
            },
        ]);

        var answer = await Service().GetMoviesAsync(CancellationToken.None);

        Assert.Null(answer.Error);
        var movie = Assert.Single(answer.Items);
        Assert.Equal("Hope", movie.Title);
        Assert.Equal(2026, movie.Year);
        Assert.Equal(1058424, movie.TmdbId);
        Assert.Equal(new DateTimeOffset(2026, 10, 13, 0, 0, 0, TimeSpan.Zero), movie.DigitalRelease);
        Assert.Equal("https://image.tmdb.org/t/p/original/p.jpg", movie.PosterUrl);
        Assert.Null(movie.BackdropUrl);
    }

    [Fact]
    public async Task TheTestAsksEveryConfiguredServiceWithoutTheCache()
    {
        _client.Status = kind => kind == ArrKind.Sonarr
            ? Task.FromResult(new ArrStatus { AppName = "Sonarr", Version = "4.0.20.3014" })
            : throw new ArrException(ArrError.Unauthorized);
        var service = Service();

        var result = await service.TestAsync(CancellationToken.None);

        Assert.Equal(new ArrTestResult(true, true, "4.0.20.3014", null), result.Sonarr);
        Assert.Equal(new ArrTestResult(true, false, null, "Unauthorized"), result.Radarr);

        _settings.Radarr = ArrEndpoint.None;
        var again = await service.TestAsync(CancellationToken.None);
        Assert.Equal(new ArrTestResult(false, false, null, "NotConfigured"), again.Radarr);
        // Due prove di Sonarr, una sola di Radarr (la seconda volta non è configurato).
        Assert.Equal(3, _client.StatusCalls.Count);
    }
}
