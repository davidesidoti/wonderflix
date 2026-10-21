using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di un'operazione sui sottotitoli (spec R §6.4); Failed: ha fallito Jellyfin o un provider.</summary>
public enum SubtitleStatus
{
    Ok,
    Forbidden,
    Invalid,
    Failed,
}

/// <summary>Esito con il valore, se c'è.</summary>
public sealed record SubtitleResult<T>(SubtitleStatus Status, T? Value);

/// <summary>
/// Cerca, scarica e carica sottotitoli per gli admin e per chi ha la spunta
/// "gestione sottotitoli" di Jellyfin (spec R §6.4): permessi e validazione,
/// il resto lo fa <see cref="ISubtitleTools"/>. Senza stato.
/// </summary>
public sealed class SubtitleService(ISubtitleTools tools, IUserDirectory users, ILibraryAccess access, ILogger<SubtitleService> logger)
{
    /// <summary>Dimensione massima di un sottotitolo caricato, decodificato (2 MiB).</summary>
    public const int MaxUploadBytes = 2 * 1024 * 1024;

    /// <summary>I formati ammessi in upload, in minuscolo.</summary>
    public static readonly IReadOnlyList<string> UploadFormats = ["srt", "ass", "ssa", "vtt", "sub"];

    public async Task<SubtitleResult<IReadOnlyList<RemoteSubtitleDto>>> SearchAsync(
        Guid userId, string? itemId, string? language, bool? perfectMatch, CancellationToken cancellationToken)
    {
        if (Check(userId, itemId, out var id) is { } rejected)
        {
            return new(rejected, null);
        }

        if (CleanLanguage(language) is not { } lang)
        {
            return new(SubtitleStatus.Invalid, null);
        }

        try
        {
            var found = await tools.SearchAsync(id, lang, perfectMatch, cancellationToken).ConfigureAwait(false);
            logger.LogDebug("Sottotitoli: ricerca per {ItemId}, {Count} risultati", Id(id), found.Count);
            return new(SubtitleStatus.Ok, found);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Sottotitoli: ricerca fallita per {ItemId}", Id(id));
            return new(SubtitleStatus.Failed, null);
        }
    }

    public async Task<SubtitleStatus> DownloadAsync(
        Guid userId, string? itemId, DownloadSubtitleRequest? request, CancellationToken cancellationToken)
    {
        if (Check(userId, itemId, out var id) is { } rejected)
        {
            return rejected;
        }

        if (string.IsNullOrWhiteSpace(request?.SubtitleId))
        {
            return SubtitleStatus.Invalid;
        }

        var subtitleId = request.SubtitleId;
        try
        {
            await tools.DownloadAsync(id, subtitleId, cancellationToken).ConfigureAwait(false);
            logger.LogDebug("Sottotitoli: scaricato per {ItemId}", Id(id));
            return SubtitleStatus.Ok;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // L'id di un sottotitolo è "<provider>_<codice>": nel log solo il provider.
            var provider = subtitleId[..Math.Max(subtitleId.IndexOf('_', StringComparison.Ordinal), 0)];
            logger.LogWarning(ex, "Sottotitoli: download fallito per {ItemId}, provider {Provider}", Id(id), provider);
            return SubtitleStatus.Failed;
        }
    }

    public async Task<SubtitleStatus> UploadAsync(
        Guid userId, string? itemId, UploadSubtitleRequest? request, CancellationToken cancellationToken)
    {
        if (Check(userId, itemId, out var id) is { } rejected)
        {
            return rejected;
        }

        var format = request?.Format?.Trim().ToLowerInvariant();
        if (request is null || CleanLanguage(request.Language) is not { } lang || format is null || !UploadFormats.Contains(format))
        {
            return SubtitleStatus.Invalid;
        }

        // Il buffer è grande quanto il massimo: un sottotitolo più lungo non ci sta e TryFromBase64String dà false.
        var buffer = new byte[MaxUploadBytes];
        if (request.Data is null || !Convert.TryFromBase64String(request.Data, buffer, out var length) || length == 0)
        {
            return SubtitleStatus.Invalid;
        }

        try
        {
            var upload = new SubtitleUpload(lang, format, request.IsForced, request.IsHearingImpaired, buffer[..length]);
            await tools.UploadAsync(id, upload, cancellationToken).ConfigureAwait(false);
            logger.LogDebug("Sottotitoli: caricato per {ItemId}, {Length} byte", Id(id), length);
            return SubtitleStatus.Ok;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Sottotitoli: upload fallito per {ItemId}", Id(id));
            return SubtitleStatus.Failed;
        }
    }

    // Tre lettere ASCII, in minuscolo; null se non lo sono. Il controllo viene prima del minuscolo (il segno Kelvin diventa "k").
    private static string? CleanLanguage(string? language) =>
        language?.Trim() is { Length: 3 } lang && lang.All(char.IsAsciiLetter) ? lang.ToLowerInvariant() : null;

    // null se chi chiama può usare i sottotitoli di quel titolo; altrimenti il motivo.
    private SubtitleStatus? Check(Guid userId, string? itemId, out Guid id)
    {
        id = Guid.Empty;
        if (users.GetUser(userId) is not { Enabled: true } user || !(user.IsAdmin || user.CanManageSubtitles))
        {
            return SubtitleStatus.Forbidden;
        }

        if (!Guid.TryParse(itemId, out id) || id == Guid.Empty)
        {
            return SubtitleStatus.Invalid;
        }

        try
        {
            return access.CanSee(userId, id) && tools.IsVideo(id) ? null : SubtitleStatus.Invalid;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Sottotitoli: la libreria non risponde per {ItemId}", Id(id));
            return SubtitleStatus.Invalid;
        }
    }

    private static string Id(Guid id) => id.ToString("N");
}
