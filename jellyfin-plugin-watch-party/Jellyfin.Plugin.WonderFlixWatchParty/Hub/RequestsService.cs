using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Gli endpoint delle richieste (spec I §7.3): Seerr per conto dell'utente
/// Seerr abbinato a chi chiama, oggetti del plugin per l'app. Lancia
/// SeerrException, che il controller traduce in risposta.
/// </summary>
public sealed class RequestsService(ISeerrClient seerr, SeerrUserMap users, SeerrTitleCache titles)
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
        return new CreatedRequestDto(created.Id, SeerrMapping.RequestStatus(created));
    }

    /// <summary>
    /// Le richieste dalla più recente: "mine" quelle di chi chiama, "pending"
    /// e "all" solo per chi può approvare. Il titolo viene da
    /// <see cref="SeerrTitleCache"/>.
    /// </summary>
    public async Task<RequestPageDto> ListAsync(
        Guid userId, string? filter, int skip, int take, string language, CancellationToken cancellationToken)
    {
        if (filter is not (FilterMine or FilterPending or FilterAll) || skip < 0 || take < 1 || take > MaxTake)
        {
            throw BadRequest();
        }

        var user = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        if (user is null)
        {
            return filter == FilterMine ? new RequestPageDto([], false) : throw NoPermission();
        }

        if (filter != FilterMine && !SeerrPermissions.CanManage(user.Permissions))
        {
            throw NoPermission();
        }

        var page = await seerr.GetRequestsAsync(
            user.Id,
            filter == FilterPending ? "pending" : "all",
            take,
            skip,
            filter == FilterMine ? user.Id : null,
            cancellationToken).ConfigureAwait(false);
        var items = await Task.WhenAll(page.Results.Select(r => ToDtoAsync(r, user.Id, language, cancellationToken)))
            .ConfigureAwait(false);
        return new RequestPageDto(items, skip + page.Results.Count < (page.PageInfo?.Results ?? 0));
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
        return await ToDtoAsync(approved, manager.Id, language, cancellationToken).ConfigureAwait(false);
    }

    public async Task<MediaRequestDto> DeclineAsync(
        Guid userId, int requestId, string language, CancellationToken cancellationToken)
    {
        Positive(requestId);
        var manager = await ManagerAsync(userId, cancellationToken).ConfigureAwait(false);
        var declined = await seerr.SetRequestStatusAsync(manager.Id, requestId, approve: false, cancellationToken)
            .ConfigureAwait(false);
        return await ToDtoAsync(declined, manager.Id, language, cancellationToken).ConfigureAwait(false);
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
        SeerrRequest request, int me, string language, CancellationToken cancellationToken)
    {
        var mediaType = MediaTypeOf(request.Media?.MediaType ?? request.Type) ?? RequestMediaTypes.Movie;
        var tmdbId = request.Media?.TmdbId ?? 0;
        var title = tmdbId > 0
            ? await titles.GetAsync(mediaType, tmdbId, language, cancellationToken).ConfigureAwait(false)
            : null;
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
            SeerrMapping.RequestStatus(request),
            SeerrMapping.Progress(request.Media?.DownloadStatus ?? []),
            SeerrMapping.JellyfinId(request.Media?.JellyfinMediaId));
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
