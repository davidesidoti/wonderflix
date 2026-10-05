using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class RequestsServiceTests
{
    private static readonly Guid Mario = Guid.Parse("150fe35a-657b-4c5e-a4fd-644c4c5152b5");
    private static readonly Guid Davide = Guid.Parse("ab8240c5-fc16-49e1-86f6-62fa00ca0fb0");
    private static readonly Guid Luigi = Guid.Parse("2c447101-5284-4cc7-9d20-3334f51e8397");
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTimeProvider _time = new();
    private readonly RequestsService _service;

    public RequestsServiceTests()
    {
        _seerr.Users.Add(new SeerrUser { Id = 3, Permissions = 34, JellyfinUserId = Davide.ToString("N"), DisplayName = "davide" });
        _seerr.Users.Add(new SeerrUser { Id = 24, Permissions = 32, JellyfinUserId = Mario.ToString("N"), DisplayName = "mario" });
        _service = new RequestsService(
            _seerr, new SeerrUserMap(_seerr, _time, NullLogger<SeerrUserMap>.Instance), new SeerrTitleCache(_seerr, _time));
    }

    private static async Task<SeerrError> ErrorOf(Func<Task> action) =>
        (await Assert.ThrowsAsync<SeerrException>(action)).Error;

    private static SeerrRequest Request(int id, int tmdbId, string type = "movie", int status = SeerrCodes.RequestPending) => new()
    {
        Id = id,
        Status = status,
        Type = type,
        CreatedAt = new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero),
        RequestedBy = new SeerrRequestUser { Id = 24, DisplayName = "mario" },
        Media = new SeerrRequestMedia { TmdbId = tmdbId, MediaType = type, Status = SeerrCodes.MediaUnknown },
    };

    [Theory]
    [InlineData("it", "it")]
    [InlineData("en", "en")]
    [InlineData("IT", "en")]
    [InlineData("ita", "en")]
    [InlineData(null, "en")]
    public void LanguageIsTwoLowercaseLettersOrEnglish(string? raw, string language) =>
        Assert.Equal(language, RequestsService.Language(raw));

    [Fact]
    public async Task MeComesFromTheAccountOrFromTheDefaults()
    {
        Assert.Equal(new RequestsMeResponse(true, false, true), await _service.MeAsync(Mario, Ct));
        Assert.Equal(new RequestsMeResponse(true, true, true), await _service.MeAsync(Davide, Ct));
        Assert.Equal(new RequestsMeResponse(true, false, false), await _service.MeAsync(Luigi, Ct));

        var noDefaults = new FakeSeerrClient { DefaultPermissions = 0 };
        var service = new RequestsService(
            noDefaults, new SeerrUserMap(noDefaults, _time, NullLogger<SeerrUserMap>.Instance), new SeerrTitleCache(noDefaults, _time));
        Assert.Equal(new RequestsMeResponse(false, false, false), await service.MeAsync(Luigi, Ct));
    }

    [Fact]
    public async Task SearchKeepsMoviesAndSeriesWithTheirStatus()
    {
        _seerr.SearchResults.AddRange(
        [
            new SeerrSearchResult
            {
                Id = 438631, MediaType = "movie", Title = "Dune", ReleaseDate = "2021-09-15", PosterPath = "/a.jpg",
                MediaInfo = new SeerrMediaInfo { Status = SeerrCodes.MediaAvailable, JellyfinMediaId = "EE39BEF06F503DD0E9DBD20593DF417F" },
            },
            new SeerrSearchResult { Id = 90228, MediaType = "tv", Name = "Dune: Prophecy", FirstAirDate = "2024-11-17" },
            new SeerrSearchResult { Id = 1, MediaType = "person", Name = "Timothée" },
            new SeerrSearchResult
            {
                Id = 2, MediaType = "movie", Title = "Bloccato", MediaInfo = new SeerrMediaInfo { Status = SeerrCodes.MediaBlocklisted },
            },
        ]);

        var titles = await _service.SearchAsync("  dune ", "it", Ct);

        Assert.Equal(("dune", "it"), Assert.Single(_seerr.Searches));
        Assert.Equal(
            new[]
            {
                new RequestableTitleDto("movie", 438631, "Dune", 2021, "/a.jpg", TitleStatuses.Available, "ee39bef06f503dd0e9dbd20593df417f"),
                new RequestableTitleDto("tv", 90228, "Dune: Prophecy", 2024, null, TitleStatuses.None, null),
            },
            titles);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public async Task SearchNeedsAQuery(string? query)
    {
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.SearchAsync(query, "it", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.SearchAsync(new string('a', RequestsService.MaxQueryLength + 1), "it", Ct)));
        Assert.Empty(_seerr.Calls);
    }

    [Fact]
    public async Task MovieDetailsSayWhoRequestedItAndWarmTheTitles()
    {
        _seerr.Movies[1170608] = new SeerrMovie
        {
            Title = "Dune - Parte tre", ReleaseDate = "2026-12-15", Overview = "Paul", Runtime = 140,
            Genres = [new() { Name = "Fantascienza" }, new() { Name = "" }],
            PosterPath = "/p.jpg", BackdropPath = "/b.jpg",
            RelatedVideos = [new() { Type = "Trailer", Site = "YouTube", Url = "https://www.youtube.com/watch?v=x" }],
            MediaInfo = new SeerrMediaInfo
            {
                Status = SeerrCodes.MediaProcessing,
                Requests = [new() { Status = SeerrCodes.RequestApproved, RequestedBy = new() { Id = 24 } }],
            },
        };

        var mario = await _service.MovieAsync(Mario, 1170608, "it", Ct);
        var davide = await _service.MovieAsync(Davide, 1170608, "it", Ct);

        Assert.Equal(
            new TitleDetailsDto(
                "movie", 1170608, "Dune - Parte tre", 2026, "Paul", mario.Genres, 140, "/p.jpg", "/b.jpg",
                "https://www.youtube.com/watch?v=x", TitleStatuses.Processing, null, true, true, null),
            mario);
        Assert.Equal(new[] { "Fantascienza" }, mario.Genres);
        Assert.False(davide.RequestedByMe);
        Assert.True(davide.Requested);

        // Il titolo è già in memoria per gli elenchi.
        _seerr.Requests.Add(Request(1, 1170608));
        await _service.ListAsync(Mario, RequestsService.FilterMine, 0, 20, "it", Ct);
        Assert.Equal(2, _seerr.Calls.Count(c => c == "GetMovie"));
    }

    [Fact]
    public async Task SeriesDetailsHaveTheSeasons()
    {
        _seerr.Shows[90228] = new SeerrTv
        {
            Name = "Dune: Prophecy", FirstAirDate = "2024-11-17",
            Seasons = [new() { SeasonNumber = 0, EpisodeCount = 1 }, new() { SeasonNumber = 1, EpisodeCount = 6 }],
        };

        var tv = await _service.TvAsync(Mario, 90228, "it", Ct);

        Assert.Equal("tv", tv.MediaType);
        Assert.Equal(new[] { new SeasonDto(1, 6, TitleStatuses.None) }, tv.Seasons);
        Assert.Equal(TitleStatuses.None, tv.Status);
    }

    [Fact]
    public async Task UnknownTitlesAndBadIdsAreErrors()
    {
        Assert.Equal(SeerrError.NotFound, await ErrorOf(() => _service.MovieAsync(Mario, 5, "it", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.TvAsync(Mario, 0, "it", Ct)));
    }

    [Fact]
    public async Task CreateImportsTheAccountAndSendsTheChosenSeasons()
    {
        _seerr.OnImport = id => new SeerrUser { Id = 30, Permissions = 32, JellyfinUserId = id.ToString("N") };

        var created = await _service.CreateAsync(
            Luigi, new CreateRequestBody { MediaType = "tv", TmdbId = 90228, Seasons = [2, 1, 2] }, Ct);

        Assert.Equal(new CreatedRequestDto(100, RequestStatuses.Pending), created);
        var (asUser, body) = Assert.Single(_seerr.Created);
        Assert.Equal(30, asUser);
        Assert.Equal("tv", body.MediaType);
        Assert.Equal(90228, body.MediaId);
        Assert.Equal(new[] { 1, 2 }, body.Seasons!);
    }

    [Fact]
    public async Task AMovieRequestHasNoSeasonsAndCanBeApprovedAtOnce()
    {
        _seerr.OnCreate = (_, body) => new SeerrRequest { Id = 7, Status = SeerrCodes.RequestApproved, Type = body.MediaType };

        var created = await _service.CreateAsync(
            Davide, new CreateRequestBody { MediaType = "movie", TmdbId = 841, Seasons = [1] }, Ct);

        Assert.Equal(new CreatedRequestDto(7, RequestStatuses.Approved), created);
        Assert.Null(Assert.Single(_seerr.Created).Body.Seasons);
        Assert.Equal(3, _seerr.Created[0].AsUser);
    }

    [Fact]
    public async Task BadRequestBodies()
    {
        foreach (var body in new CreateRequestBody?[]
                 {
                     null,
                     new() { MediaType = "movie", TmdbId = 0 },
                     new() { MediaType = "person", TmdbId = 1 },
                     new() { MediaType = "tv", TmdbId = 1 },
                     new() { MediaType = "tv", TmdbId = 1, Seasons = [] },
                     new() { MediaType = "tv", TmdbId = 1, Seasons = [0] },
                 })
        {
            Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.CreateAsync(Mario, body, Ct)));
        }

        Assert.Empty(_seerr.Calls);
    }

    [Fact]
    public async Task MineUsesRequestedByAndCompletesTheTitles()
    {
        _seerr.Movies[841] = new SeerrMovie { Title = "Dune", ReleaseDate = "1984-12-14", PosterPath = "/d.jpg" };
        var tv = Request(2, 59941, "tv", SeerrCodes.RequestApproved);
        tv.Seasons = [new() { SeasonNumber = 14 }, new() { SeasonNumber = 13 }];
        tv.Media!.JellyfinMediaId = "6D1C8EA33A794F76FDBE92A216959073";
        _seerr.Requests.AddRange([Request(1, 841), tv]);
        _seerr.TotalRequests = 3;

        var page = await _service.ListAsync(Mario, RequestsService.FilterMine, 0, 2, "it", Ct);

        Assert.Equal((24, "all", 2, 0, (int?)24), Assert.Single(_seerr.Listed));
        Assert.True(page.HasMore);
        var movie = page.Items[0];
        Assert.Equal(
            new MediaRequestDto(
                1, "movie", 841, "Dune", 1984, "/d.jpg", movie.Seasons, new RequesterDto("mario", true),
                new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero), RequestStatuses.Pending, null, null),
            movie);
        Assert.Empty(movie.Seasons);
        // Seerr non conosce il titolo della serie: resta vuoto.
        Assert.Equal(string.Empty, page.Items[1].Title);
        Assert.Equal(new[] { 13, 14 }, page.Items[1].Seasons);
        Assert.Equal("6d1c8ea33a794f76fdbe92a216959073", page.Items[1].JellyfinItemId);
        Assert.Equal(RequestStatuses.Approved, page.Items[1].Status);
    }

    [Fact]
    public async Task PendingAndAllAreForManagersOnly()
    {
        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.ListAsync(Mario, RequestsService.FilterPending, 0, 20, "it", Ct)));
        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.ListAsync(Luigi, RequestsService.FilterAll, 0, 20, "it", Ct)));

        var page = await _service.ListAsync(Davide, RequestsService.FilterPending, 20, 20, "it", Ct);

        Assert.Equal((3, "pending", 20, 20, (int?)null), Assert.Single(_seerr.Listed));
        Assert.False(page.HasMore);
    }

    [Fact]
    public async Task MineWithoutAnAccountIsEmptyAndBadPagesAreErrors()
    {
        var page = await _service.ListAsync(Luigi, RequestsService.FilterMine, 0, 20, "it", Ct);

        Assert.Empty(page.Items);
        Assert.False(page.HasMore);
        Assert.Empty(_seerr.Listed);
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.ListAsync(Mario, "altro", 0, 20, "it", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.ListAsync(Mario, RequestsService.FilterMine, -1, 20, "it", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.ListAsync(Mario, RequestsService.FilterMine, 0, RequestsService.MaxTake + 1, "it", Ct)));
    }

    [Fact]
    public async Task ServicesForManagersWithout4k()
    {
        _seerr.Servers[SeerrServices.Radarr] =
        [
            new() { Id = 0, Name = "Radarr", IsDefault = true, ActiveProfileId = 8, ActiveDirectory = "/media/movies" },
            new() { Id = 1, Name = "Radarr Anime", ActiveProfileId = 7, ActiveDirectory = "/media/anime" },
            new() { Id = 2, Name = "Radarr 4K", Is4k = true },
        ];
        _seerr.ServerDetails[(SeerrServices.Radarr, 0)] = new SeerrServerDetails
        {
            Profiles = [new() { Id = 8, Name = "Main Profile" }],
            RootFolders = [new() { Path = "/media/movies" }, new() { Path = null }],
        };
        _seerr.ServerDetails[(SeerrServices.Radarr, 1)] = new SeerrServerDetails
        {
            Profiles = [new() { Id = 7, Name = "Anime Main Profile" }],
            RootFolders = [new() { Path = "/media/anime" }],
        };

        var services = await _service.ServicesAsync(Davide, "movie", Ct);

        Assert.Equal(
            new[] { "Radarr", "Radarr Anime" }, services.Select(s => s.Name));
        Assert.Equal(new ProfileDto(8, "Main Profile"), Assert.Single(services[0].Profiles));
        Assert.Equal(new[] { "/media/movies" }, services[0].RootFolders);
        Assert.True(services[0].IsDefault);
        Assert.Equal(7, services[1].DefaultProfileId);
        Assert.Equal("/media/anime", services[1].DefaultRootFolder);
        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.ServicesAsync(Mario, "movie", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.ServicesAsync(Davide, "music", Ct)));
    }

    [Fact]
    public async Task ApproveWithTheDefaultsDoesNotChangeTheRequest()
    {
        _seerr.Requests.Add(Request(53, 841));
        _seerr.Movies[841] = new SeerrMovie { Title = "Dune" };

        var approved = await _service.ApproveAsync(Davide, 53, new ApproveBody(), "it", Ct);

        Assert.Empty(_seerr.Updated);
        Assert.Equal((3, 53, true), Assert.Single(_seerr.StatusChanges));
        Assert.Equal(RequestStatuses.Approved, approved.Status);
        Assert.Equal("Dune", approved.Title);
        Assert.False(approved.RequestedBy.IsMe);
    }

    [Fact]
    public async Task ApproveWithAServerChangesTheRequestFirst()
    {
        var tv = Request(60, 59941, "tv");
        tv.Seasons = [new() { SeasonNumber = 1 }, new() { SeasonNumber = 2 }];
        _seerr.Requests.Add(tv);

        await _service.ApproveAsync(
            Davide, 60, new ApproveBody { ServerId = 0, ProfileId = 8, RootFolder = "/media/anime" }, "it", Ct);

        var (asUser, requestId, body) = Assert.Single(_seerr.Updated);
        Assert.Equal((3, 60), (asUser, requestId));
        Assert.Equal("tv", body.MediaType);
        Assert.Equal(0, body.ServerId);
        Assert.Equal(8, body.ProfileId);
        Assert.Equal("/media/anime", body.RootFolder);
        Assert.Equal(new[] { 1, 2 }, body.Seasons!);
        Assert.Equal(new[] { "GetUsers", "GetRequest", "UpdateRequest", "Approve", "GetTv" }, _seerr.Calls);
    }

    [Fact]
    public async Task ApproveAndDeclineNeedAManagerAndAWholeChoice()
    {
        _seerr.Requests.Add(Request(53, 841));

        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.ApproveAsync(Mario, 53, null, "it", Ct)));
        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.DeclineAsync(Mario, 53, "it", Ct)));
        Assert.Equal(
            SeerrError.BadRequest,
            await ErrorOf(() => _service.ApproveAsync(Davide, 53, new ApproveBody { ServerId = 1 }, "it", Ct)));
        Assert.Equal(SeerrError.NotFound, await ErrorOf(() => _service.DeclineAsync(Davide, 99, "it", Ct)));

        var declined = await _service.DeclineAsync(Davide, 53, "it", Ct);

        Assert.Equal(RequestStatuses.Declined, declined.Status);
        Assert.Equal((3, 53, false), _seerr.StatusChanges.Last());
    }
}
