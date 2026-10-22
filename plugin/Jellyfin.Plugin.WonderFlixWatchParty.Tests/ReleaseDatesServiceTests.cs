using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ReleaseDatesServiceTests
{
    private static readonly DateTimeOffset Cinema = new(2026, 9, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset Digital = new(2026, 11, 12, 0, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset Physical = new(2026, 12, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset Next = new(2026, 11, 2, 1, 0, 0, TimeSpan.Zero);

    private readonly FakeArrClient _client = new();
    private readonly FakeArrSettings _settings = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 22, 12, 0, 0, TimeSpan.Zero));
    private readonly RecordingLogger<ReleaseDatesService> _logger = new();

    private ReleaseDatesService Service() => new(_client, _settings, _time, _logger);

    private static RadarrMovie Movie() => new()
    {
        TmdbId = 83533,
        InCinemas = Cinema,
        DigitalRelease = Digital,
        PhysicalRelease = Physical,
    };

    private static SonarrEpisode Episode(int season, int number) =>
        new() { SeriesId = 40, SeasonNumber = season, EpisodeNumber = number, AirDateUtc = Next };

    [Fact]
    public async Task AMovieInRadarrGivesItsDates()
    {
        _client.FindMovies = _ => Task.FromResult<IReadOnlyList<RadarrMovie?>>([null, Movie()]);

        var dates = await Service().GetMovieAsync(83533, CancellationToken.None);

        Assert.Equal(new MovieDates(Cinema, Digital, Physical, false), dates);
        Assert.Empty(_client.LookupCalls);
    }

    [Fact]
    public async Task AMovieNotInRadarrUsesTheLookup()
    {
        _client.Lookup = _ => Task.FromResult(Movie());

        var dates = await Service().GetMovieAsync(83533, CancellationToken.None);

        Assert.Equal(new MovieDates(Cinema, Digital, Physical, false), dates);
        Assert.Single(_client.LookupCalls);
    }

    [Fact]
    public async Task RadarrFailingGivesNoDates()
    {
        _client.FindMovies = _ => Task.FromException<IReadOnlyList<RadarrMovie?>>(new ArrException(ArrError.Unreachable));

        Assert.Null(await Service().GetMovieAsync(83533, CancellationToken.None));
    }

    [Fact]
    public async Task OneReadPerMovieEvenWhenAskedTogether()
    {
        _client.FindMovies = _ => Task.FromResult<IReadOnlyList<RadarrMovie?>>([Movie()]);
        var service = Service();

        await Task.WhenAll(Enumerable.Range(0, 10).Select(_ => service.GetMovieAsync(83533, CancellationToken.None)));

        Assert.Single(_client.FindMovieCalls);
    }

    [Fact]
    public async Task NotConfiguredAsksNothing()
    {
        _settings.Radarr = ArrEndpoint.None;
        _settings.Sonarr = ArrEndpoint.None;
        var service = Service();

        Assert.Null(await service.GetMovieAsync(83533, CancellationToken.None));
        Assert.Null(await service.GetSeriesAsync(452595, 259909, CancellationToken.None));
        Assert.Empty(_client.FindMovieCalls);
        Assert.Empty(_client.LookupCalls);
        Assert.Equal(0, _client.SeriesCalls);
    }

    [Fact]
    public async Task TheSeriesIsFoundByTvdbThenTmdb()
    {
        _client.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
        [
            new SonarrSeries { Id = 40, TvdbId = 452595, TmdbId = 1, NextAiring = Next },
            new SonarrSeries { Id = 41, TvdbId = 7, TmdbId = 259909, NextAiring = Next.AddDays(1) },
        ]);
        var service = Service();

        var byTvdb = await service.GetSeriesAsync(452595, 0, CancellationToken.None);
        var byTmdb = await service.GetSeriesAsync(null, 259909, CancellationToken.None);

        Assert.Equal(Next, byTvdb?.NextAiring);
        Assert.Equal(Next.AddDays(1), byTmdb?.NextAiring);
        Assert.Equal(1, _client.SeriesCalls);
    }

    [Fact]
    public async Task TheNextEpisodeHasItsNumbers()
    {
        _client.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
            [new SonarrSeries { Id = 40, TvdbId = 452595, NextAiring = Next }]);
        _client.SeriesEpisodes = _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(
            [Episode(0, 1), null, Episode(1, 4)]);

        var next = await Service().GetSeriesAsync(452595, 0, CancellationToken.None);

        Assert.Equal(new SeriesNext(Next, 1, 4), next);
        Assert.Equal([40], _client.SeriesEpisodeCalls);
    }

    [Fact]
    public async Task EpisodesFailingKeepTheDate()
    {
        _client.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
            [new SonarrSeries { Id = 40, TvdbId = 452595, NextAiring = Next }]);
        _client.SeriesEpisodes = _ => Task.FromException<IReadOnlyList<SonarrEpisode?>>(new ArrException(ArrError.Unreachable));

        var next = await Service().GetSeriesAsync(452595, 0, CancellationToken.None);

        Assert.Equal(new SeriesNext(Next, null, null), next);
    }

    [Fact]
    public async Task ASeriesWithoutNextAiringHasNoNext()
    {
        _client.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
            [new SonarrSeries { Id = 40, TvdbId = 452595 }]);

        Assert.Null(await Service().GetSeriesAsync(452595, 0, CancellationToken.None));
        Assert.Empty(_client.SeriesEpisodeCalls);
    }
}
