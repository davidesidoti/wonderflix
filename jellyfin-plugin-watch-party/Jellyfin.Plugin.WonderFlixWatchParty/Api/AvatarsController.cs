using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// I tag delle immagini degli utenti chiesti, per ogni utente autenticato
/// (spec K §7.2): l'app li mostra per gli amici, i membri del party e la
/// chat. Mai l'elenco completo: solo gli utenti chiesti. Come il resto del
/// plugin, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class AvatarsController(IUserAvatars avatars) : ControllerBase
{
    /// <summary>Voci al massimo per chiamata, sommando id e nomi.</summary>
    public const int MaxEntries = 100;

    /// <summary>Gli utenti chiesti per id e per nome, separati da virgole.</summary>
    [HttpGet("Users/Avatars")]
    public ActionResult<AvatarsResponse> GetAvatars([FromQuery] string? ids, [FromQuery] string? names)
    {
        var idValues = Split(ids);
        var nameValues = Split(names);
        if (idValues.Count + nameValues.Count > MaxEntries)
        {
            return BadRequest();
        }

        // Un id che non è un GUID non è di nessuno.
        var parsedIds = idValues
            .Select(raw => Guid.TryParse(raw, out var id) ? id : Guid.Empty)
            .Where(id => id != Guid.Empty)
            .ToList();
        return new AvatarsResponse(avatars.Find(parsedIds, nameValues)
            .Select(user => new AvatarEntry(user.Id.ToString("N"), user.Name, user.ImageTag))
            .ToList());
    }

    private static List<string> Split(string? raw) =>
        string.IsNullOrWhiteSpace(raw)
            ? []
            : [.. raw.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)];
}
