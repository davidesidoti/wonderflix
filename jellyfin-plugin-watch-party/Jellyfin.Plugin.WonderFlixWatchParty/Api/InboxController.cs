using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// La cassetta delle notifiche (spec G §6.3): per ogni utente autenticato,
/// anche senza accesso ai watch party; gli annunci e i nuovi titoli in attesa
/// solo per gli admin. Chi chiama è l'utente dell'autenticazione. Come il
/// resto del plugin, mai 404: l'id di una voce è una stringa (un vincolo di
/// rotta risponderebbe 404).
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class InboxController(
    IAuthorizationContext authorizationContext,
    InboxService inbox,
    NewTitlesCollector newTitles,
    INewTitlesSettings newTitlesSettings) : ControllerBase
{
    /// <summary>Le voci dalla più recente e quante non lette.</summary>
    [HttpGet("Inbox")]
    public async Task<ActionResult<InboxResponse>> GetInbox() =>
        inbox.Get(await CallerAsync().ConfigureAwait(false));

    /// <summary>Segna lette le voci fino a UpTo (il Seq della più recente vista).</summary>
    [HttpPost("Inbox/Read")]
    public async Task<ActionResult> MarkRead([FromBody] InboxReadRequest? request)
    {
        if (request is null)
        {
            return BadRequest();
        }

        await inbox.MarkReadAsync(await CallerAsync().ConfigureAwait(false), request.UpTo).ConfigureAwait(false);
        return NoContent();
    }

    /// <summary>Toglie una voce; 204 anche se non c'è.</summary>
    [HttpDelete("Inbox/Entries/{entryId}")]
    public async Task<ActionResult> RemoveEntry([FromRoute] string entryId)
    {
        await inbox.RemoveAsync(await CallerAsync().ConfigureAwait(false), entryId).ConfigureAwait(false);
        return NoContent();
    }

    /// <summary>Svuota la cassetta di chi chiama.</summary>
    [HttpDelete("Inbox")]
    public async Task<ActionResult> Clear()
    {
        await inbox.ClearAsync(await CallerAsync().ConfigureAwait(false)).ConfigureAwait(false);
        return NoContent();
    }

    /// <summary>Un annuncio a tutti gli utenti attivi; solo per gli admin (dalla pagina nella Dashboard).</summary>
    [HttpPost("Inbox/Announcements")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<AnnouncementResponse>> Announce([FromBody] AnnouncementRequest? request)
    {
        var result = await inbox.AnnounceAsync(request?.Text).ConfigureAwait(false);
        return result.Status == HubStatus.Ok ? result.Value! : BadRequest();
    }

    /// <summary>La casella dei nuovi titoli e quanti ne aspettano (pagina della Dashboard); solo per gli admin.</summary>
    [HttpGet("Inbox/NewTitles")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public ActionResult<NewTitlesStatus> GetNewTitles() =>
        new NewTitlesStatus(newTitlesSettings.NotifyNewTitles, newTitles.Pending);

    /// <summary>Chiude subito l'ondata dei nuovi titoli ("Send now"); solo per gli admin.</summary>
    [HttpPost("Inbox/NewTitles/Send")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<NewTitlesSendResponse>> SendNewTitles() =>
        await newTitles.SendNowAsync().ConfigureAwait(false);

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
