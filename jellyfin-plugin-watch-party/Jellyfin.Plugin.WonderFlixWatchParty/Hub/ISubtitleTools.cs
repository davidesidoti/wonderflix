using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un sottotitolo da salvare accanto al video (spec R §6.4); Language minuscolo a tre lettere, Format minuscolo.</summary>
public sealed record SubtitleUpload(string Language, string Format, bool IsForced, bool IsHearingImpaired, byte[] Data);

/// <summary>I sottotitoli di Jellyfin (adattatore di ISubtitleManager e IProviderManager).</summary>
public interface ISubtitleTools
{
    /// <summary>L'elemento è un film o un episodio.</summary>
    bool IsVideo(Guid itemId);

    Task<IReadOnlyList<RemoteSubtitleDto>> SearchAsync(Guid itemId, string language, bool? perfectMatch, CancellationToken cancellationToken);

    /// <summary>Scarica e mette in coda il refresh dell'elemento; lancia se il download fallisce.</summary>
    Task DownloadAsync(Guid itemId, string subtitleId, CancellationToken cancellationToken);

    /// <summary>Salva e mette in coda il refresh dell'elemento; lancia se il salvataggio fallisce.</summary>
    Task UploadAsync(Guid itemId, SubtitleUpload upload, CancellationToken cancellationToken);
}
