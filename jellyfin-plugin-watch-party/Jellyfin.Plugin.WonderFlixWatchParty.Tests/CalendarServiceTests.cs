using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class CalendarServiceTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 22, 14, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Start = new(2026, 9, 28);
    private static readonly DateOnly End = new(2026, 11, 9);

    private readonly FakeTimeProvider _time = new(Now);
    private readonly FakeArrClient _client = new();
    private readonly FakeArrSettings _settings = new();
    private readonly FakeSeriesIndex _index = new();
    private readonly FakeServer _server = new();
    private readonly RecordingLogger<CalendarService> _logger = new();

    private CalendarService Service() => new(_client, _settings, _index, _server, _time, _logger);

    private static SonarrEpisode Episode(int number, bool hasFile = false) => new()
    {
        SeriesId = 1,
        SeasonNumber = 2,
        EpisodeNumber = number,
        Title = $"Episodio {number}",
        AirDateUtc = new DateTimeOffset(2026, 10, 5, 2, 0, 0, TimeSpan.Zero).AddDays(number),
        HasFile = hasFile,
        Series = new SonarrSeries { Title = "The Bear", TvdbId = 136311 },
    };

    private static RadarrMovie Movie(int tmdbId, bool hasFile = false) => new()
    {
        Title = $"Film {tmdbId}",
        Year = 2026,
        TmdbId = tmdbId,
        DigitalRelease = new DateTimeOffset(2026, 10, 6, 0, 0, 0, TimeSpan.Zero),
        HasFile = hasFile,
    };

    private void Releases(SonarrEpisode[] episodes, RadarrMovie[] movies)
    {
        _client.Episodes = (_, _) => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(episodes);
        _client.Movies = (_, _) => Task.FromResult<IReadOnlyList<RadarrMovie?>>(movies);
    }

    [Fact]
    public void IsValidPeriodChecksOrderAndLength()
    {
        Assert.False(CalendarService.IsValidPeriod(new DateOnly(2026, 10, 1), new DateOnly(2026, 10, 1)));
        Assert.True(CalendarService.IsValidPeriod(new DateOnly(2026, 10, 1), new DateOnly(2026, 10, 2)));
        Assert.True(CalendarService.IsValidPeriod(Start, End));
        Assert.False(CalendarService.IsValidPeriod(Start, new DateOnly(2026, 11, 10)));
        Assert.False(CalendarService.IsValidPeriod(new DateOnly(1, 1, 1), new DateOnly(1, 1, 2)));
        Assert.False(CalendarService.IsValidPeriod(new DateOnly(9999, 12, 30), new DateOnly(9999, 12, 31)));
    }

    [Fact]
    public async Task TheServicesAreAskedWithADayOfMarginEachSide()
    {
        await Service().GetAsync(Guid.Empty, Start, End, CancellationToken.None);

        var from = new DateTimeOffset(2026, 9, 27, 0, 0, 0, TimeSpan.Zero);
        var to = new DateTimeOffset(2026, 11, 10, 0, 0, 0, TimeSpan.Zero);
        Assert.Equal((from, to), Assert.Single(_client.EpisodeCalls));
        Assert.Equal((from, to), Assert.Single(_client.MovieCalls));
    }

    [Fact]
    public async Task DownloadedReleasesAreOnServer()
    {
        Releases([Episode(1, hasFile: true), Episode(3)], [Movie(10, hasFile: true), Movie(11)]);

        var answer = await Service().GetAsync(Guid.Empty, Start, End, CancellationToken.None);

        Assert.Null(answer.SeriesError);
        Assert.Null(answer.MoviesError);
        Assert.Equal([true, false], answer.Episodes.Select(e => e.OnServer));
        Assert.Equal([true, false], answer.Movies.OrderBy(m => m.TmdbId).Select(m => m.OnServer));
        Assert.Equal("The Bear", answer.Episodes[0].SeriesName);
        Assert.Equal(2026, answer.Movies[0].Year);
    }

    [Fact]
    public async Task EachUserGetsTheLibraryIdsOnlyWhenTheySeeThem()
    {
        var mario = _server.AddUser("mario");
        var luigi = _server.AddUser("luigi");
        var series = Guid.NewGuid();
        var movie = Guid.NewGuid();
        _index.Series.Add(new LibrarySeries(series, "136311", null, null));
        _index.Movies.Add(new LibraryMovie(movie, "10"));
        _server.Unseen.Add((luigi.Id, series));
        _server.Unseen.Add((luigi.Id, movie));
        Releases([Episode(1)], [Movie(10)]);
        var service = Service();

        var forMario = await service.GetAsync(mario.Id, Start, End, CancellationToken.None);
        var forLuigi = await service.GetAsync(luigi.Id, Start, End, CancellationToken.None);

        Assert.Equal(series.ToString("N"), Assert.Single(forMario.Episodes).JellyfinSeriesId);
        Assert.Equal(movie.ToString("N"), Assert.Single(forMario.Movies).JellyfinItemId);
        Assert.Null(Assert.Single(forLuigi.Episodes).JellyfinSeriesId);
        Assert.Null(Assert.Single(forLuigi.Movies).JellyfinItemId);
        Assert.Single(_client.EpisodeCalls);
    }

    [Fact]
    public async Task OneServiceFailingKeepsTheOther()
    {
        Releases([], [Movie(10)]);
        _client.Episodes = (_, _) => throw new ArrException(ArrError.Unreachable);

        var answer = await Service().GetAsync(Guid.Empty, Start, End, CancellationToken.None);

        Assert.Equal("Unreachable", answer.SeriesError);
        Assert.Empty(answer.Episodes);
        Assert.Single(answer.Movies);
        Assert.Null(answer.MoviesError);
    }

    [Fact]
    public async Task NotConfiguredServicesAreNotCalled()
    {
        _settings.Sonarr = ArrEndpoint.None;

        var answer = await Service().GetAsync(Guid.Empty, Start, End, CancellationToken.None);

        Assert.Equal("NotConfigured", answer.SeriesError);
        Assert.Empty(answer.Episodes);
        Assert.Null(answer.MoviesError);
        Assert.Empty(_client.EpisodeCalls);
        Assert.Single(_client.MovieCalls);
    }

    [Fact]
    public async Task PeriodsAreCachedSeparately()
    {
        var service = Service();
        var first = new DateOnly(2026, 10, 1);

        await service.GetAsync(Guid.Empty, first, first.AddDays(1), CancellationToken.None);
        await service.GetAsync(Guid.Empty, first, first.AddDays(1), CancellationToken.None);
        Assert.Single(_client.EpisodeCalls);
        Assert.Single(_client.MovieCalls);

        // Sette periodi diversi: il primo esce dalla cache (ne tiene sei).
        for (var day = 1; day <= 6; day++)
        {
            await service.GetAsync(Guid.Empty, first.AddDays(day), first.AddDays(day + 1), CancellationToken.None);
        }

        Assert.Equal(7, _client.EpisodeCalls.Count);
        await service.GetAsync(Guid.Empty, first, first.AddDays(1), CancellationToken.None);
        Assert.Equal(8, _client.EpisodeCalls.Count);
        Assert.Equal(8, _client.MovieCalls.Count);
    }

    [Fact]
    public async Task TheLibraryFailingKeepsTheReleases()
    {
        var mario = _server.AddUser("mario");
        _index.Series.Add(new LibrarySeries(Guid.NewGuid(), "136311", null, null));
        _index.Fails = true;
        Releases([Episode(1)], [Movie(10)]);

        var answer = await Service().GetAsync(mario.Id, Start, End, CancellationToken.None);

        Assert.Null(Assert.Single(answer.Episodes).JellyfinSeriesId);
        Assert.Null(Assert.Single(answer.Movies).JellyfinItemId);
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Warning);
    }
}
