using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Seerr finto, in memoria: dati da preparare e chiamate registrate per nome.</summary>
internal sealed class FakeSeerrClient : ISeerrClient
{
    public string Version { get; set; } = "3.4.1";

    public List<SeerrUser> Users { get; } = [];

    public int DefaultPermissions { get; set; } = SeerrPermissions.Request;

    public List<SeerrSearchResult> SearchResults { get; } = [];

    public Dictionary<int, SeerrMovie> Movies { get; } = [];

    public Dictionary<int, SeerrTv> Shows { get; } = [];

    /// <summary>Tutte le richieste: GetRequests ne dà una pagina, Approve e Decline le cambiano.</summary>
    public List<SeerrRequest> Requests { get; } = [];

    /// <summary>Totale per pageInfo; -1 = quante sono in <see cref="Requests"/>.</summary>
    public int TotalRequests { get; set; } = -1;

    public Dictionary<string, List<SeerrServer>> Servers { get; } = [];

    public Dictionary<(string Service, int Id), SeerrServerDetails> ServerDetails { get; } = [];

    /// <summary>Se impostato, ogni chiamata lancia questo errore.</summary>
    public SeerrError? FailWith { get; set; }

    /// <summary>Errore solo per la chiamata con quel nome (es. "Import", "CreateRequest").</summary>
    public Dictionary<string, SeerrError> FailOn { get; } = [];

    /// <summary>Il nome di ogni chiamata, in ordine.</summary>
    public List<string> Calls { get; } = [];

    public List<(string Query, string Language)> Searches { get; } = [];

    public List<(int AsUser, SeerrCreateRequest Body)> Created { get; } = [];

    public List<(int AsUser, string Filter, int Take, int Skip, int? RequestedBy)> Listed { get; } = [];

    public List<(int AsUser, int RequestId, SeerrUpdateRequest Body)> Updated { get; } = [];

    public List<(int AsUser, int RequestId, bool Approve)> StatusChanges { get; } = [];

    /// <summary>L'utente che l'import crea per un id Jellyfin; null = l'import riesce ma non crea nessuno.</summary>
    public Func<Guid, SeerrUser?> OnImport { get; set; } = _ => null;

    /// <summary>La risposta a una nuova richiesta.</summary>
    public Func<int, SeerrCreateRequest, SeerrRequest> OnCreate { get; set; } =
        (_, body) => new SeerrRequest { Id = 100, Status = SeerrCodes.RequestPending, Type = body.MediaType };

    public Task<SeerrStatusInfo> GetStatusAsync(CancellationToken cancellationToken)
    {
        Call("GetStatus");
        return Task.FromResult(new SeerrStatusInfo { Version = Version });
    }

    public Task<SeerrUser> GetMeAsync(CancellationToken cancellationToken)
    {
        Call("GetMe");
        return Task.FromResult(new SeerrUser { Id = 1, Permissions = SeerrPermissions.Admin });
    }

    public Task<IReadOnlyList<SeerrUser>> GetUsersAsync(CancellationToken cancellationToken)
    {
        Call("GetUsers");
        return Task.FromResult<IReadOnlyList<SeerrUser>>(Users.ToList());
    }

    public Task ImportJellyfinUserAsync(Guid jellyfinUserId, CancellationToken cancellationToken)
    {
        Call("Import");
        if (OnImport(jellyfinUserId) is { } user)
        {
            Users.Add(user);
        }

        return Task.CompletedTask;
    }

    public Task<SeerrMainSettings> GetMainSettingsAsync(CancellationToken cancellationToken)
    {
        Call("GetMainSettings");
        return Task.FromResult(new SeerrMainSettings { DefaultPermissions = DefaultPermissions });
    }

    public Task<IReadOnlyList<SeerrSearchResult>> SearchAsync(
        string query, string language, CancellationToken cancellationToken)
    {
        Call("Search");
        Searches.Add((query, language));
        return Task.FromResult<IReadOnlyList<SeerrSearchResult>>(SearchResults.ToList());
    }

    public Task<SeerrMovie> GetMovieAsync(int tmdbId, string language, CancellationToken cancellationToken)
    {
        Call("GetMovie");
        return Movies.TryGetValue(tmdbId, out var movie)
            ? Task.FromResult(movie)
            : throw new SeerrException(SeerrError.NotFound);
    }

    public Task<SeerrTv> GetTvAsync(int tmdbId, string language, CancellationToken cancellationToken)
    {
        Call("GetTv");
        return Shows.TryGetValue(tmdbId, out var tv)
            ? Task.FromResult(tv)
            : throw new SeerrException(SeerrError.NotFound);
    }

    public Task<SeerrRequest> CreateRequestAsync(int asUser, SeerrCreateRequest body, CancellationToken cancellationToken)
    {
        Call("CreateRequest");
        Created.Add((asUser, body));
        return Task.FromResult(OnCreate(asUser, body));
    }

    public Task<SeerrPage<SeerrRequest>> GetRequestsAsync(
        int asUser, string filter, int take, int skip, int? requestedBy, CancellationToken cancellationToken)
    {
        Call("GetRequests");
        Listed.Add((asUser, filter, take, skip, requestedBy));
        return Task.FromResult(new SeerrPage<SeerrRequest>
        {
            Results = Requests.Skip(skip).Take(take).ToList(),
            PageInfo = new SeerrPageInfo { Results = TotalRequests < 0 ? Requests.Count : TotalRequests },
        });
    }

    public Task<SeerrRequest> GetRequestAsync(int asUser, int requestId, CancellationToken cancellationToken)
    {
        Call("GetRequest");
        return Task.FromResult(Find(requestId));
    }

    public Task UpdateRequestAsync(int asUser, int requestId, SeerrUpdateRequest body, CancellationToken cancellationToken)
    {
        Call("UpdateRequest");
        Updated.Add((asUser, requestId, body));
        return Task.CompletedTask;
    }

    public Task<SeerrRequest> SetRequestStatusAsync(
        int asUser, int requestId, bool approve, CancellationToken cancellationToken)
    {
        Call(approve ? "Approve" : "Decline");
        StatusChanges.Add((asUser, requestId, approve));
        var request = Find(requestId);
        request.Status = approve ? SeerrCodes.RequestApproved : SeerrCodes.RequestDeclined;
        return Task.FromResult(request);
    }

    public Task<IReadOnlyList<SeerrServer>> GetServersAsync(string service, CancellationToken cancellationToken)
    {
        Call("GetServers");
        return Task.FromResult<IReadOnlyList<SeerrServer>>(Servers.GetValueOrDefault(service) ?? []);
    }

    public Task<SeerrServerDetails> GetServerDetailsAsync(string service, int serverId, CancellationToken cancellationToken)
    {
        Call("GetServerDetails");
        return Task.FromResult(ServerDetails[(service, serverId)]);
    }

    private SeerrRequest Find(int requestId) =>
        Requests.FirstOrDefault(r => r.Id == requestId) ?? throw new SeerrException(SeerrError.NotFound);

    private void Call(string name)
    {
        Calls.Add(name);
        if (FailWith is { } error)
        {
            throw new SeerrException(error);
        }

        if (FailOn.TryGetValue(name, out var one))
        {
            throw new SeerrException(one);
        }
    }
}
