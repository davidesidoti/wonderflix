namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>
/// Le chiamate a Seerr che servono al plugin (spec I §7.2). asUser è l'id
/// Seerr per conto di cui si agisce (X-API-User); le altre agiscono come
/// l'utente 1 (admin). Lanciano solo SeerrException, o
/// OperationCanceledException se si annulla chi chiama.
/// </summary>
public interface ISeerrClient
{
    Task<SeerrStatusInfo> GetStatusAsync(CancellationToken cancellationToken);

    /// <summary>L'utente della chiave: serve a provarla.</summary>
    Task<SeerrUser> GetMeAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<SeerrUser>> GetUsersAsync(CancellationToken cancellationToken);

    Task ImportJellyfinUserAsync(Guid jellyfinUserId, CancellationToken cancellationToken);

    Task<SeerrMainSettings> GetMainSettingsAsync(CancellationToken cancellationToken);

    /// <summary>La prima pagina della ricerca (film, serie e persone).</summary>
    Task<IReadOnlyList<SeerrSearchResult>> SearchAsync(string query, string language, CancellationToken cancellationToken);

    Task<SeerrMovie> GetMovieAsync(int tmdbId, string language, CancellationToken cancellationToken);

    Task<SeerrTv> GetTvAsync(int tmdbId, string language, CancellationToken cancellationToken);

    Task<SeerrRequest> CreateRequestAsync(int asUser, SeerrCreateRequest body, CancellationToken cancellationToken);

    /// <summary>Le richieste dalla più recente; filter "all" o "pending", requestedBy per le proprie.</summary>
    Task<SeerrPage<SeerrRequest>> GetRequestsAsync(
        int asUser, string filter, int take, int skip, int? requestedBy, CancellationToken cancellationToken);

    Task<SeerrRequest> GetRequestAsync(int asUser, int requestId, CancellationToken cancellationToken);

    Task UpdateRequestAsync(int asUser, int requestId, SeerrUpdateRequest body, CancellationToken cancellationToken);

    /// <summary>Approva o rifiuta; restituisce la richiesta aggiornata.</summary>
    Task<SeerrRequest> SetRequestStatusAsync(int asUser, int requestId, bool approve, CancellationToken cancellationToken);

    /// <summary>I server di un servizio (<see cref="SeerrServices"/>).</summary>
    Task<IReadOnlyList<SeerrServer>> GetServersAsync(string service, CancellationToken cancellationToken);

    Task<SeerrServerDetails> GetServerDetailsAsync(string service, int serverId, CancellationToken cancellationToken);
}
