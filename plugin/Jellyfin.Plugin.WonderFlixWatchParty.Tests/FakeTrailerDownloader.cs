using System.Collections.Concurrent;
using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Downloader finto: scrive un file piccolo se l'esito è Ok; Gate tiene il download aperto, Throw lo fa lanciare.</summary>
internal sealed class FakeTrailerDownloader : ITrailerDownloader
{
    private int _calls;
    private int _running;
    private int _maxRunning;

    public TrailerDownloadOutcome Outcome { get; set; } = TrailerDownloadOutcome.Ok;

    public bool Throw { get; set; }

    public Task? Gate { get; set; }

    /// <summary>Gate per video: il download di quell'id resta aperto finché non lo si completa.</summary>
    public ConcurrentDictionary<string, TaskCompletionSource> Gates { get; } = new();

    /// <summary>Il token ricevuto dall'ultima chiamata.</summary>
    public CancellationToken LastToken { get; private set; }

    public int MaxRunning => Volatile.Read(ref _maxRunning);

    public int DownloadCalls => Volatile.Read(ref _calls);

    /// <summary>Gli id dei download partiti, in ordine: ci entrano quando sono già contati in MaxRunning.</summary>
    public ConcurrentQueue<string> Started { get; } = new();

    public async Task<TrailerDownloadOutcome> DownloadAsync(string videoId, string targetMp4Path, CancellationToken cancellationToken)
    {
        // Il token prima del conteggio: chi vede DownloadCalls salire trova già il token giusto.
        LastToken = cancellationToken;
        Interlocked.Increment(ref _calls);
        var running = Interlocked.Increment(ref _running);
        int max;
        while ((max = Volatile.Read(ref _maxRunning)) < running && Interlocked.CompareExchange(ref _maxRunning, running, max) != max)
        {
        }

        Started.Enqueue(videoId);

        try
        {
            if (Gates.TryGetValue(videoId, out var own))
            {
                await own.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
            }
        }
        finally
        {
            Interlocked.Decrement(ref _running);
        }

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
