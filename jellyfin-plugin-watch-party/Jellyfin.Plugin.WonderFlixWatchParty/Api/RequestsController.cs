using System.Globalization;
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Le richieste con Seerr (spec I §7.3), per ogni utente autenticato: chi
/// chiama è l'utente dell'autenticazione, mai un campo della richiesta. Gli
/// errori sono stato HTTP più {Code}. Come il resto del plugin, mai 404:
/// gli id sono stringhe senza vincoli di rotta.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Requests")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class RequestsController(
    IAuthorizationContext authorizationContext,
    RequestsService requests,
    ISeerrSettings settings,
    ISeerrClient seerr,
    RequestWebhookHandler webhook) : ControllerBase
{
    /// <summary>Richieste per pagina se l'app non lo dice.</summary>
    public const int DefaultTake = 20;

    /// <summary>Cosa può fare chi chiama.</summary>
    [HttpGet("Me")]
    public Task<ActionResult<RequestsMeResponse>> Me() =>
        RunAsync((user, ct) => requests.MeAsync(user, ct));

    /// <summary>Film e serie di Seerr per la sezione "Da richiedere".</summary>
    [HttpGet("Search")]
    public Task<ActionResult<IReadOnlyList<RequestableTitleDto>>> Search(
        [FromQuery] string? query, [FromQuery] string? language) =>
        RunAsync((_, ct) => requests.SearchAsync(query, RequestsService.Language(language), ct));

    [HttpGet("Movie/{tmdbId}")]
    public Task<ActionResult<TitleDetailsDto>> Movie([FromRoute] string tmdbId, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.MovieAsync(user, Id(tmdbId), RequestsService.Language(language), ct));

    [HttpGet("Tv/{tmdbId}")]
    public Task<ActionResult<TitleDetailsDto>> Tv([FromRoute] string tmdbId, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.TvAsync(user, Id(tmdbId), RequestsService.Language(language), ct));

    /// <summary>Una richiesta per conto di chi chiama.</summary>
    [HttpPost("")]
    public Task<ActionResult<CreatedRequestDto>> Create([FromBody] CreateRequestBody? body) =>
        RunAsync((user, ct) => requests.CreateAsync(user, body, ct));

    /// <summary>Le richieste: filter "mine", "pending" o "all".</summary>
    [HttpGet("")]
    public Task<ActionResult<RequestPageDto>> List(
        [FromQuery] string? filter, [FromQuery] int? skip, [FromQuery] int? take, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.ListAsync(
            user, filter, skip ?? 0, take ?? DefaultTake, RequestsService.Language(language), ct));

    /// <summary>I server per la finestra Approva; mediaType "movie" o "tv".</summary>
    [HttpGet("Services/{mediaType}")]
    public Task<ActionResult<IReadOnlyList<ServiceDto>>> Services([FromRoute] string mediaType) =>
        RunAsync((user, ct) => requests.ServicesAsync(user, mediaType, ct));

    [HttpPost("{requestId}/Approve")]
    public Task<ActionResult<MediaRequestDto>> Approve(
        [FromRoute] string requestId, [FromBody] ApproveBody? body, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.ApproveAsync(user, Id(requestId), body, RequestsService.Language(language), ct));

    [HttpPost("{requestId}/Decline")]
    public Task<ActionResult<MediaRequestDto>> Decline([FromRoute] string requestId, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.DeclineAsync(user, Id(requestId), RequestsService.Language(language), ct));

    /// <summary>"Prova collegamento" della pagina del plugin; solo per gli admin. Sempre 200.</summary>
    [HttpPost("Test")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<SeerrTestResponse>> Test()
    {
        if (!settings.IsConfigured())
        {
            return new SeerrTestResponse(false, null, "NotConfigured");
        }

        try
        {
            var status = await seerr.GetStatusAsync(HttpContext.RequestAborted).ConfigureAwait(false);
            await seerr.GetMeAsync(HttpContext.RequestAborted).ConfigureAwait(false);
            return new SeerrTestResponse(true, status.Version, null);
        }
        catch (SeerrException ex)
        {
            return new SeerrTestResponse(false, null, ex.Error == SeerrError.Auth ? "SeerrAuth" : "SeerrUnavailable");
        }
    }

    /// <summary>Configurato e ultimo evento del webhook (pagina del plugin); solo per gli admin.</summary>
    [HttpGet("Admin")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public ActionResult<RequestsAdminStatus> Admin()
    {
        var (at, type) = webhook.LastEvent;
        return new RequestsAdminStatus(settings.IsConfigured(), at, type);
    }

    /// <summary>Da errore di Seerr a stato HTTP e {Code} (spec I §7.3).</summary>
    internal static ObjectResult Error(SeerrError error)
    {
        var (status, code) = error switch
        {
            SeerrError.NotConfigured => (StatusCodes.Status503ServiceUnavailable, "NotConfigured"),
            SeerrError.Unavailable => (StatusCodes.Status502BadGateway, "SeerrUnavailable"),
            SeerrError.Auth => (StatusCodes.Status502BadGateway, "SeerrAuth"),
            SeerrError.NoPermission => (StatusCodes.Status403Forbidden, "NoPermission"),
            SeerrError.QuotaExceeded => (StatusCodes.Status403Forbidden, "QuotaExceeded"),
            SeerrError.Blocklisted => (StatusCodes.Status403Forbidden, "Blocklisted"),
            SeerrError.AlreadyRequested => (StatusCodes.Status409Conflict, "AlreadyRequested"),
            SeerrError.NothingToRequest => (StatusCodes.Status409Conflict, "NothingToRequest"),
            SeerrError.AccountUnavailable => (StatusCodes.Status409Conflict, "AccountUnavailable"),
            SeerrError.NotFound => (StatusCodes.Status400BadRequest, "UnknownRequest"),
            _ => (StatusCodes.Status400BadRequest, "Invalid"),
        };
        return new ObjectResult(new RequestsErrorDto(code)) { StatusCode = status };
    }

    private static int Id(string raw) =>
        int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var id) && id > 0
            ? id
            : throw new SeerrException(SeerrError.BadRequest);

    private async Task<ActionResult<T>> RunAsync<T>(Func<Guid, CancellationToken, Task<T>> action)
    {
        if (!settings.IsConfigured())
        {
            return Error(SeerrError.NotConfigured);
        }

        var userId = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        try
        {
            // Costruito a mano: ActionResult<T> non converte da un tipo interfaccia.
            return new ActionResult<T>(await action(userId, HttpContext.RequestAborted).ConfigureAwait(false));
        }
        catch (SeerrException ex)
        {
            return Error(ex.Error);
        }
    }
}
