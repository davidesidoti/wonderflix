using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Providers;
using MediaBrowser.Controller.Subtitles;
using MediaBrowser.Model.IO;
using MediaBrowser.Model.Providers;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// I sottotitoli di Jellyfin (spec R §6.4). Verificato sul sorgente di 10.11.9 (firme anche a 10.11.0):
/// - ISubtitleManager.SearchSubtitles(video, language, isPerfectMatch, isAutomated, ct): array vuoto per tipi diversi da Movie/Episode.
/// - DownloadSubtitles rilancia l'errore del provider: il 204 sempre è di SubtitleController, che lo inghiotte; qui l'errore esce.
/// - UploadSubtitle lancia ArgumentException per un formato che Jellyfin non ammette.
/// - Dopo download e upload, come SubtitleController: QueueRefresh con MetadataRefreshOptions(DirectoryService) e RefreshPriority.High.
/// - RemoteSubtitleInfo: i booleani sono nullable (null = false); AiTranslated || MachineTranslated vale MachineTranslated.
/// </summary>
public sealed class JellyfinSubtitleTools(
    ILibraryManager libraryManager,
    ISubtitleManager subtitleManager,
    IProviderManager providerManager,
    IFileSystem fileSystem,
    ILogger<JellyfinSubtitleTools> logger) : ISubtitleTools
{
    public bool IsVideo(Guid itemId) => FindVideo(itemId) is not null;

    public async Task<IReadOnlyList<RemoteSubtitleDto>> SearchAsync(
        Guid itemId, string language, bool? perfectMatch, CancellationToken cancellationToken)
    {
        var found = await subtitleManager.SearchSubtitles(RequireVideo(itemId), language, perfectMatch, false, cancellationToken)
            .ConfigureAwait(false);
        return found.Select(s => new RemoteSubtitleDto(
            s.Id ?? string.Empty,
            s.ProviderName ?? string.Empty,
            s.Name ?? string.Empty,
            s.ThreeLetterISOLanguageName ?? string.Empty,
            s.Format ?? string.Empty,
            s.CommunityRating,
            s.DownloadCount,
            s.IsHashMatch == true,
            s.HearingImpaired == true,
            s.Forced == true,
            s.AiTranslated == true || s.MachineTranslated == true)).ToList();
    }

    public async Task DownloadAsync(Guid itemId, string subtitleId, CancellationToken cancellationToken)
    {
        var video = RequireVideo(itemId);
        await subtitleManager.DownloadSubtitles(video, subtitleId, cancellationToken).ConfigureAwait(false);
        QueueRefresh(video);
    }

    public async Task UploadAsync(Guid itemId, SubtitleUpload upload, CancellationToken cancellationToken)
    {
        var video = RequireVideo(itemId);
        var stream = new MemoryStream(upload.Data, writable: false);
        await using (stream.ConfigureAwait(false))
        {
            await subtitleManager.UploadSubtitle(video, new SubtitleResponse
            {
                Language = upload.Language,
                Format = upload.Format,
                IsForced = upload.IsForced,
                IsHearingImpaired = upload.IsHearingImpaired,
                Stream = stream,
            }).ConfigureAwait(false);
        }

        QueueRefresh(video);
    }

    // Con un id vuoto GetItemById lancia: l'elemento non c'è e basta.
    private Video? FindVideo(Guid itemId) =>
        itemId != Guid.Empty && libraryManager.GetItemById(itemId) is (Movie or Episode) and Video video ? video : null;

    private Video RequireVideo(Guid itemId) =>
        FindVideo(itemId) ?? throw new InvalidOperationException("L'elemento non è un film né un episodio");

    // Il refresh è un di più: se il sottotitolo è già salvato, un suo errore non deve far fallire la chiamata.
    private void QueueRefresh(Video video)
    {
        try
        {
            providerManager.QueueRefresh(video.Id, new MetadataRefreshOptions(new DirectoryService(fileSystem)), RefreshPriority.High);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Sottotitoli: refresh non accodato per {ItemId}", video.Id.ToString("N"));
        }
    }
}
