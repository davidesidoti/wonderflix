using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>I sottotitoli di Jellyfin finti: ricorda le chiamate e può fallire.</summary>
internal sealed class FakeSubtitleTools : ISubtitleTools
{
    public HashSet<Guid> Videos { get; } = [];

    public List<RemoteSubtitleDto> Results { get; } = [];

    /// <summary>Lanciata da Download e Upload.</summary>
    public Exception? Failure { get; set; }

    /// <summary>IsVideo lancia.</summary>
    public bool LibraryFails { get; set; }

    public List<(Guid ItemId, string Language, bool? PerfectMatch)> Searches { get; } = [];

    public List<(Guid ItemId, string SubtitleId)> Downloads { get; } = [];

    public List<(Guid ItemId, SubtitleUpload Upload)> Uploads { get; } = [];

    public bool IsVideo(Guid itemId) =>
        LibraryFails ? throw new InvalidOperationException("libreria non disponibile") : Videos.Contains(itemId);

    public Task<IReadOnlyList<RemoteSubtitleDto>> SearchAsync(Guid itemId, string language, bool? perfectMatch, CancellationToken cancellationToken)
    {
        Searches.Add((itemId, language, perfectMatch));
        return Task.FromResult<IReadOnlyList<RemoteSubtitleDto>>([.. Results]);
    }

    public Task DownloadAsync(Guid itemId, string subtitleId, CancellationToken cancellationToken)
    {
        Downloads.Add((itemId, subtitleId));
        return Failure is null ? Task.CompletedTask : Task.FromException(Failure);
    }

    public Task UploadAsync(Guid itemId, SubtitleUpload upload, CancellationToken cancellationToken)
    {
        Uploads.Add((itemId, upload));
        return Failure is null ? Task.CompletedTask : Task.FromException(Failure);
    }
}
