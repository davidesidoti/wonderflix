using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Le collezioni (BoxSet) con i loro titoli, per ogni utente autenticato
/// (spec K §7.1): Jellyfin non dice in quali collezioni sta un film, e le
/// collezioni stanno in una cartella che gli utenti non vedono. Una
/// collezione senza titoli visibili non c'è. Come il resto del plugin, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class CollectionsController(
    IAuthorizationContext authorizationContext,
    ICollectionDirectory collections) : ControllerBase
{
    /// <summary>Le collezioni di chi chiama, con gli id dei titoli che vede.</summary>
    [HttpGet("Collections")]
    public async Task<ActionResult<CollectionsResponse>> GetCollections()
    {
        var caller = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        var found = await collections.GetCollectionsAsync(caller).ConfigureAwait(false);
        return new CollectionsResponse(found
            .Where(collection => collection.ItemIds.Count > 0)
            .Select(collection => new CollectionEntry(
                collection.Id.ToString("N"),
                collection.Name,
                collection.SortName,
                collection.PrimaryImageTag,
                collection.DateCreated,
                collection.ItemIds.Select(id => id.ToString("N")).ToList()))
            .ToList());
    }
}
