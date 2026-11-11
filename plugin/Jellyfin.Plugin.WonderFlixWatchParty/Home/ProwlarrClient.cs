using System.Globalization;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// HTTP verso Prowlarr (API v1), con X-Api-Key. Stessa strada e stessa classificazione degli errori di
/// <see cref="ArrClient"/>; nel registro vanno solo servizio, percorso ed esito: mai la chiave, mai la query.
/// </summary>
public sealed class ProwlarrClient(
    IHttpClientFactory httpClientFactory,
    IArrSettings settings,
    ILogger<ProwlarrClient> logger) : IProwlarrClient
{
    /// <summary>Attesa massima di una ricerca: gli indexer rispondono piano.</summary>
    public static readonly TimeSpan QueryTimeout = TimeSpan.FromMinutes(2);

    public async Task<IReadOnlyList<ProwlarrRelease>> SearchAsync(ProwlarrQuery query, CancellationToken cancellationToken)
    {
        var path = new StringBuilder("search?type=")
            .Append(Uri.EscapeDataString(query.Type))
            .Append("&query=")
            .Append(Uri.EscapeDataString(query.Query));
        if (query.Season is { } season)
        {
            path.Append("&season=").Append(season.ToString(CultureInfo.InvariantCulture));
        }

        if (query.Episode is { } episode)
        {
            path.Append("&ep=").Append(episode.ToString(CultureInfo.InvariantCulture));
        }

        foreach (var id in query.IndexerIds)
        {
            path.Append("&indexerIds=").Append(id.ToString(CultureInfo.InvariantCulture));
        }

        foreach (var category in query.Categories)
        {
            path.Append("&categories=").Append(category.ToString(CultureInfo.InvariantCulture));
        }

        return await ArrClient.SendToServiceAsync<List<ProwlarrRelease>>(
            httpClientFactory,
            logger,
            "Prowlarr",
            settings.Prowlarr,
            "v1",
            HttpMethod.Get,
            path.ToString(),
            null,
            QueryTimeout,
            async (response, token) =>
                await response.Content.ReadFromJsonAsync<List<ProwlarrRelease>>(ArrJson.Options, token).ConfigureAwait(false)
                ?? throw new JsonException("risposta vuota"),
            cancellationToken).ConfigureAwait(false);
    }
}
