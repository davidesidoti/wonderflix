using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Gli endpoint delle richieste (spec I §7.3): Seerr per conto dell'utente
/// Seerr abbinato a chi chiama, oggetti del plugin per l'app. Lancia
/// SeerrException, che il controller traduce in risposta.
/// </summary>
public sealed class RequestsService(
    ISeerrClient seerr,
    SeerrUserMap users,
    SeerrTitleCache titles,
    SeerrRequestList list,
    ReleaseDatesService dates,
    DownloadService downloads,
    TimeProvider time)
{
    /// <summary>Richieste al massimo per pagina.</summary>
    public const int MaxTake = 50;

    /// <summary>Lunghezza massima di una ricerca.</summary>
    public const int MaxQueryLength = 100;

    /// <summary>Stagioni al massimo in una richiesta di serie (nessuna serie ne ha di più).</summary>
    public const int MaxSeasons = 100;

    public const string FilterMine = "mine";
    public const string FilterPending = "pending";
    public const string FilterAll = "all";

    /// <summary>La lingua per TMDB dalla lingua dell'app: due lettere minuscole, altrimenti "en".</summary>
    public static string Language(string? raw) =>
        raw is { Length: 2 } && raw.All(char.IsAsciiLetterLower) ? raw : "en";

    /// <summary>
    /// Cosa può fare chi chiama. Senza account vale ciò che Seerr darebbe al
    /// nuovo account (l'import arriva con la prima richiesta).
    /// </summary>
    public async Task<RequestsMeResponse> MeAsync(Guid userId, CancellationToken cancellationToken)
    {
        var user = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        if (user is null)
        {
            var defaults = await users.DefaultPermissionsAsync(cancellationToken).ConfigureAwait(false);
            return new RequestsMeResponse(SeerrPermissions.CanRequest(defaults), CanManage: false, HasAccount: false);
        }

        return new RequestsMeResponse(
            SeerrPermissions.CanRequest(user.Permissions), SeerrPermissions.CanManage(user.Permissions), HasAccount: true);
    }

    /// <summary>La prima pagina di Seerr, solo film e serie, senza i titoli bloccati.</summary>
    public async Task<IReadOnlyList<RequestableTitleDto>> SearchAsync(
        string? query, string language, CancellationToken cancellationToken)
    {
        var trimmed = query?.Trim() ?? string.Empty;
        if (trimmed.Length == 0 || trimmed.Length > MaxQueryLength)
        {
            throw BadRequest();
        }

        var results = await seerr.SearchAsync(trimmed, language, cancellationToken).ConfigureAwait(false);
        var titles = new List<RequestableTitleDto>();
        foreach (var result in results)
        {
            var mediaType = MediaTypeOf(result.MediaType);
            if (mediaType is null || SeerrMapping.IsBlocklisted(result.MediaInfo))
            {
                continue;
            }

            var tv = mediaType == RequestMediaTypes.Tv;
            titles.Add(new RequestableTitleDto(
                mediaType,
                result.Id,
                (tv ? result.Name : result.Title) ?? string.Empty,
                SeerrMapping.Year(tv ? result.FirstAirDate : result.ReleaseDate),
                result.PosterPath,
                SeerrMapping.TitleStatus(result.MediaInfo?.Status),
                SeerrMapping.JellyfinId(result.MediaInfo?.JellyfinMediaId)));
        }

        return titles;
    }

    public async Task<TitleDetailsDto> MovieAsync(
        Guid userId, int tmdbId, string language, CancellationToken cancellationToken)
    {
        Positive(tmdbId);
        var movie = await seerr.GetMovieAsync(tmdbId, language, cancellationToken).ConfigureAwait(false);
        var me = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        titles.Put(RequestMediaTypes.Movie, tmdbId, language, SeerrTitleCache.From(movie));
        var info = movie.MediaInfo;
        return new TitleDetailsDto(
            RequestMediaTypes.Movie,
            tmdbId,
            movie.Title ?? string.Empty,
            SeerrMapping.Year(movie.ReleaseDate),
            movie.Overview,
            SeerrMapping.Genres(movie.Genres),
            movie.Runtime,
            movie.PosterPath,
            movie.BackdropPath,
            SeerrMapping.TrailerUrl(movie.RelatedVideos),
            SeerrMapping.TitleStatus(info?.Status),
            SeerrMapping.JellyfinId(info?.JellyfinMediaId),
            SeerrMapping.RequestedBy(info, me?.Id),
            SeerrMapping.Requested(info),
            Seasons: null);
    }

    public async Task<TitleDetailsDto> TvAsync(
        Guid userId, int tmdbId, string language, CancellationToken cancellationToken)
    {
        Positive(tmdbId);
        var tv = await seerr.GetTvAsync(tmdbId, language, cancellationToken).ConfigureAwait(false);
        var me = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        titles.Put(RequestMediaTypes.Tv, tmdbId, language, SeerrTitleCache.From(tv));
        var info = tv.MediaInfo;
        return new TitleDetailsDto(
            RequestMediaTypes.Tv,
            tmdbId,
            tv.Name ?? string.Empty,
            SeerrMapping.Year(tv.FirstAirDate),
            tv.Overview,
            SeerrMapping.Genres(tv.Genres),
            RuntimeMinutes: null,
            tv.PosterPath,
            tv.BackdropPath,
            SeerrMapping.TrailerUrl(tv.RelatedVideos),
            SeerrMapping.TitleStatus(info?.Status),
            SeerrMapping.JellyfinId(info?.JellyfinMediaId),
            SeerrMapping.RequestedBy(info, me?.Id),
            SeerrMapping.Requested(info),
            SeerrMapping.Seasons(tv));
    }

    /// <summary>Una richiesta per conto di chi chiama, con l'import se non ha un account (spec I §7.2).</summary>
    public async Task<CreatedRequestDto> CreateAsync(
        Guid userId, CreateRequestBody? body, CancellationToken cancellationToken)
    {
        var mediaType = MediaTypeOf(body?.MediaType);
        if (body is null || mediaType is null || body.TmdbId <= 0)
        {
            throw BadRequest();
        }

        List<int>? seasons = null;
        if (mediaType == RequestMediaTypes.Tv)
        {
            seasons = body.Seasons?.Distinct().Order().ToList() ?? [];
            if (seasons.Count == 0 || seasons.Count > MaxSeasons || seasons.Any(s => s <= 0))
            {
                throw BadRequest();
            }
        }

        var user = await users.EnsureAsync(userId, cancellationToken).ConfigureAwait(false);
        var created = await seerr.CreateRequestAsync(
            user.Id,
            new SeerrCreateRequest { MediaType = mediaType, MediaId = body.TmdbId, Seasons = seasons },
            cancellationToken).ConfigureAwait(false);
        list.Clear();
        return new CreatedRequestDto(created.Id, SeerrMapping.RequestStatus(created));
    }

    /// <summary>
    /// Le richieste dalla più recente: "mine" quelle di chi chiama, "pending"
    /// e "all" solo per chi può approvare. Il titolo viene da
    /// <see cref="SeerrTitleCache"/>. Con <paramref name="group"/> (non per "pending")
    /// solo le richieste di quel gruppo, con il loro numero in Total (spec richieste-ui §4).
    /// </summary>
    public async Task<RequestPageDto> ListAsync(
        Guid userId, string? filter, string? group, int skip, int take, string language, CancellationToken cancellationToken)
    {
        if (filter is not (FilterMine or FilterPending or FilterAll) || skip < 0 || take < 1 || take > MaxTake
            || (group is not null && (!RequestGroups.IsGroup(group) || filter == FilterPending)))
        {
            throw BadRequest();
        }

        var user = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        if (user is null)
        {
            return filter == FilterMine ? new RequestPageDto([], false, group is null ? null : 0) : throw NoPermission();
        }

        if (filter != FilterMine && !SeerrPermissions.CanManage(user.Permissions))
        {
            throw NoPermission();
        }

        if (group is not null)
        {
            return await GroupAsync(user.Id, filter == FilterMine ? user.Id : null, group, skip, take, language, cancellationToken)
                .ConfigureAwait(false);
        }

        var page = await seerr.GetRequestsAsync(
            user.Id,
            filter == FilterPending ? "pending" : "all",
            take,
            skip,
            filter == FilterMine ? user.Id : null,
            cancellationToken).ConfigureAwait(false);
        var items = await Task.WhenAll(page.Results.Select(r => ToDtoAsync(r, user.Id, language, grouped: false, cancellationToken)))
            .ConfigureAwait(false);
        return new RequestPageDto(items, skip + page.Results.Count < (page.PageInfo?.Results ?? 0));
    }

    /// <summary>Una pagina di un gruppo, dall'elenco intero di <see cref="SeerrRequestList"/> (nell'ordine di Seerr).</summary>
    private async Task<RequestPageDto> GroupAsync(
        int me, int? requestedBy, string group, int skip, int take, string language, CancellationToken cancellationToken)
    {
        var all = await list.GetAsync(me, requestedBy, cancellationToken).ConfigureAwait(false);
        var now = time.GetUtcNow();
        var movies = await Task.WhenAll(all.Select(r => RequestGroups.NeedsMovieDates(r, now)
                ? dates.GetMovieAsync(r.Media?.TmdbId ?? 0, cancellationToken)
                : Task.FromResult<MovieDates?>(null)))
            .ConfigureAwait(false);
        var inGroup = all.Where((r, i) => RequestGroups.GroupOf(RequestGroups.StatusOf(r, movies[i], now)) == group).ToList();
        var items = await Task.WhenAll(inGroup.Skip(skip).Take(take)
                .Select(r => ToDtoAsync(r, me, language, grouped: true, cancellationToken)))
            .ConfigureAwait(false);
        return new RequestPageDto(items, skip + items.Length < inGroup.Count, inGroup.Count);
    }

    /// <summary>I server non 4K del servizio del tipo (Radarr per i film, Sonarr per le serie), per chi può approvare.</summary>
    public async Task<IReadOnlyList<ServiceDto>> ServicesAsync(
        Guid userId, string? mediaType, CancellationToken cancellationToken)
    {
        var type = MediaTypeOf(mediaType) ?? throw BadRequest();
        await ManagerAsync(userId, cancellationToken).ConfigureAwait(false);
        var service = type == RequestMediaTypes.Tv ? SeerrServices.Sonarr : SeerrServices.Radarr;
        var servers = (await seerr.GetServersAsync(service, cancellationToken).ConfigureAwait(false))
            .Where(s => !s.Is4k)
            .ToList();
        var details = await Task.WhenAll(servers.Select(s => DetailsOrNullAsync(service, s.Id, cancellationToken)))
            .ConfigureAwait(false);

        // Un server che Seerr non riesce a leggere si salta: gli altri restano.
        return servers
            .Zip(details, (server, detail) => detail is null
                ? null
                : new ServiceDto(
                    server.Id,
                    server.Name ?? string.Empty,
                    server.IsDefault,
                    detail.Profiles.Select(p => new ProfileDto(p.Id, p.Name ?? string.Empty)).ToList(),
                    detail.RootFolders.Select(f => f.Path).OfType<string>().ToList(),
                    server.ActiveProfileId,
                    server.ActiveDirectory))
            .OfType<ServiceDto>()
            .ToList();
    }

    /// <summary>
    /// Approva. Senza scelte valgono i predefiniti di Seerr; con server,
    /// profilo e cartella (tutti e tre) la richiesta si cambia prima (spec I §7.3).
    /// </summary>
    public async Task<MediaRequestDto> ApproveAsync(
        Guid userId, int requestId, ApproveBody? body, string language, CancellationToken cancellationToken)
    {
        Positive(requestId);
        var manager = await ManagerAsync(userId, cancellationToken).ConfigureAwait(false);
        var choice = body ?? new ApproveBody();
        if (choice.ServerId is not null || choice.ProfileId is not null || choice.RootFolder is not null)
        {
            if (choice.ServerId is not { } serverId || serverId < 0
                || choice.ProfileId is not { } profileId || profileId <= 0
                || string.IsNullOrWhiteSpace(choice.RootFolder))
            {
                throw BadRequest();
            }

            var request = await seerr.GetRequestAsync(manager.Id, requestId, cancellationToken).ConfigureAwait(false);
            var mediaType = MediaTypeOf(request.Type ?? request.Media?.MediaType) ?? RequestMediaTypes.Movie;
            await seerr.UpdateRequestAsync(
                manager.Id,
                requestId,
                new SeerrUpdateRequest
                {
                    MediaType = mediaType,
                    ServerId = serverId,
                    ProfileId = profileId,
                    RootFolder = choice.RootFolder,
                    Seasons = mediaType == RequestMediaTypes.Tv
                        ? request.Seasons.Select(s => s.SeasonNumber).ToList()
                        : null,
                },
                cancellationToken).ConfigureAwait(false);
        }

        var approved = await seerr.SetRequestStatusAsync(manager.Id, requestId, approve: true, cancellationToken)
            .ConfigureAwait(false);
        list.Clear();
        // Seerr aggiunge il titolo a Radarr/Sonarr: un giro dei download parte tra poco (spec T §5, decisione 7).
        downloads.Nudge();
        return await ToDtoAsync(approved, manager.Id, language, grouped: false, cancellationToken).ConfigureAwait(false);
    }

    public async Task<MediaRequestDto> DeclineAsync(
        Guid userId, int requestId, string language, CancellationToken cancellationToken)
    {
        Positive(requestId);
        var manager = await ManagerAsync(userId, cancellationToken).ConfigureAwait(false);
        var declined = await seerr.SetRequestStatusAsync(manager.Id, requestId, approve: false, cancellationToken)
            .ConfigureAwait(false);
        list.Clear();
        return await ToDtoAsync(declined, manager.Id, language, grouped: false, cancellationToken).ConfigureAwait(false);
    }

    private async Task<SeerrServerDetails?> DetailsOrNullAsync(
        string service, int serverId, CancellationToken cancellationToken)
    {
        try
        {
            return await seerr.GetServerDetailsAsync(service, serverId, cancellationToken).ConfigureAwait(false);
        }
        catch (SeerrException)
        {
            return null;
        }
    }

    private async Task<MediaRequestDto> ToDtoAsync(
        SeerrRequest request, int me, string language, bool grouped, CancellationToken cancellationToken)
    {
        var mediaType = MediaTypeOf(request.Media?.MediaType ?? request.Type) ?? RequestMediaTypes.Movie;
        var tmdbId = request.Media?.TmdbId ?? 0;
        var now = time.GetUtcNow();

        // Con i gruppi c'è anche Tolta dal server; Non trovata si decide dopo le date (un film non ancora uscito resta in corso).
        var status = grouped ? RequestGroups.StatusOf(request, null, now) : SeerrMapping.RequestStatus(request);

        // Le date si chiedono solo dove servono (un film già disponibile, rifiutato o fallito non le mostra)
        // e insieme al titolo; ReleaseDatesService non lancia.
        var titleTask = tmdbId > 0
            ? titles.GetAsync(mediaType, tmdbId, language, cancellationToken)
            : Task.FromResult<SeerrTitle?>(null);
        var movieTask = mediaType == RequestMediaTypes.Movie && tmdbId > 0
            && status is not (RequestStatuses.Available or RequestStatuses.Declined or RequestStatuses.Failed or RequestStatuses.Removed)
            ? dates.GetMovieAsync(tmdbId, cancellationToken)
            : Task.FromResult<MovieDates?>(null);
        var seriesTask = mediaType == RequestMediaTypes.Tv
            ? dates.GetSeriesAsync(request.Media?.TvdbId, tmdbId, cancellationToken)
            : Task.FromResult<SeriesNext?>(null);
        await Task.WhenAll(titleTask, movieTask, seriesTask).ConfigureAwait(false);
        var title = await titleTask.ConfigureAwait(false);
        var movie = await movieTask.ConfigureAwait(false);
        var series = await seriesTask.ConfigureAwait(false);

        if (grouped)
        {
            status = RequestGroups.StatusOf(request, movie, now);
        }
        else if (status == RequestStatuses.Approved && ReleaseRules.IsAwaitingRelease(movie, now))
        {
            status = RequestStatuses.AwaitingRelease;
        }

        return new MediaRequestDto(
            request.Id,
            mediaType,
            tmdbId,
            title?.Title ?? string.Empty,
            title?.Year,
            title?.PosterPath,
            request.Seasons.Select(s => s.SeasonNumber).Order().ToList(),
            new RequesterDto(request.RequestedBy?.DisplayName ?? string.Empty, request.RequestedBy?.Id == me),
            request.CreatedAt,
            status,
            SeerrMapping.Progress(request.Media?.DownloadStatus ?? []),
            // Tolta dal server: l'id di Seerr porterebbe a un elemento che non c'è più.
            status == RequestStatuses.Removed ? null : SeerrMapping.JellyfinId(request.Media?.JellyfinMediaId),
            movie?.InCinemas,
            movie?.DigitalRelease,
            series?.NextAiring,
            series?.SeasonNumber,
            series?.EpisodeNumber);
    }

    private async Task<SeerrUser> ManagerAsync(Guid userId, CancellationToken cancellationToken)
    {
        var user = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        return user is not null && SeerrPermissions.CanManage(user.Permissions) ? user : throw NoPermission();
    }

    private static string? MediaTypeOf(string? raw) => raw switch
    {
        RequestMediaTypes.Movie => RequestMediaTypes.Movie,
        RequestMediaTypes.Tv => RequestMediaTypes.Tv,
        _ => null,
    };

    private static void Positive(int id)
    {
        if (id <= 0)
        {
            throw BadRequest();
        }
    }

    private static SeerrException BadRequest() => new(SeerrError.BadRequest);

    private static SeerrException NoPermission() => new(SeerrError.NoPermission);
}
