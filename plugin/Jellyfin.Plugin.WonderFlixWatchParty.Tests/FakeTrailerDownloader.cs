using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Downloader finto: scrive un file piccolo se l'esito è Ok; Gate tiene il download aperto, Throw lo fa lanciare.</summary>
internal sealed class FakeTrailerDownloader : ITrailerDownloader
{
    private int _calls;

    public TrailerDownloadOutcome Outcome { get; set; } = TrailerDownloadOutcome.Ok;

    public bool Throw { get; set; }

    public Task? Gate { get; set; }

    public int DownloadCalls => Volatile.Read(ref _calls);

    public async Task<TrailerDownloadOutcome> DownloadAsync(string videoId, string targetMp4Path, CancellationToken cancellationToken)
    {
        Interlocked.Increment(ref _calls);
        if (Gate is { } gate)
        {
            await gate.ConfigureAwait(false);
        }

        if (Throw)
        {
            throw new InvalidOperationException("boom");
        }

        if (Outcome == TrailerDownloadOutcome.Ok)
        {
            await File.WriteAllBytesAsync(targetMp4Path, [1, 2, 3], cancellationToken).ConfigureAwait(false);
        }

        return Outcome;
    }
}
