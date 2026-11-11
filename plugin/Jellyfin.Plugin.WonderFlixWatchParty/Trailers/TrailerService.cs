using System.Collections.Concurrent;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>Gli stati di <see cref="TrailerStatusDto.State"/>.</summary>
public static class TrailerStates
{
    public const string None = "None";
    public const string Downloading = "Downloading";
    public const string Ready = "Ready";
    public const string Failed = "Failed";
}

/// <summary>
/// Dal titolo al file del trailer: lo risolve, lo scarica una volta sola per tutti gli utenti e lo tiene in cache.
/// Il download gira anche se la richiesta si chiude. La chiave è l'id del video, e vale solo se il risolutore l'ha dato di recente.
/// </summary>
public sealed class TrailerService(
    TrailerResolver resolver, ITrailerDownloader downloader, TrailerCache cache, ILogger<TrailerService> logger)
{
    // Un job fallito resta qui, perché chi interroga veda "Failed"; il prossimo StartAsync lo sostituisce.
    private readonly ConcurrentDictionary<string, Task<TrailerDownloadOutcome>> _jobs = new();
    private readonly object _gate = new();

    public async Task<TrailerInfoDto> InfoAsync(Guid userId, TrailerSubject subject, CancellationToken cancellationToken)
    {
        var resolved = await resolver.ResolveAsync(userId, subject, cancellationToken).ConfigureAwait(false);
        return new TrailerInfoDto(resolved is not null, resolved?.Name);
    }

    public async Task<TrailerStatusDto> StartAsync(Guid userId, TrailerSubject subject, CancellationToken cancellationToken)
    {
        if (await resolver.ResolveAsync(userId, subject, cancellationToken).ConfigureAwait(false) is not { } resolved)
        {
            return new TrailerStatusDto(null, TrailerStates.None);
        }

        var id = resolved.VideoId;
        if (cache.Has(id))
        {
            return new TrailerStatusDto(id, TrailerStates.Ready);
        }

        lock (_gate)
        {
            if (cache.Has(id))
            {
                return new TrailerStatusDto(id, TrailerStates.Ready);
            }

            if (!_jobs.TryGetValue(id, out var job) || job.IsCompleted)
            {
                cache.MakeRoom();
                _jobs[id] = Task.Run(() => DownloadAsync(id), CancellationToken.None);
            }
        }

        return new TrailerStatusDto(id, TrailerStates.Downloading);
    }

    /// <summary>Lo stato del trailer; null se la chiave non è mai uscita da qui (→ 404).</summary>
    public TrailerStatusDto? Status(string key)
    {
        if (!resolver.WasResolved(key))
        {
            return null;
        }

        if (_jobs.TryGetValue(key, out var job))
        {
            if (!job.IsCompleted)
            {
                return new TrailerStatusDto(key, TrailerStates.Downloading);
            }

            if (job.Result != TrailerDownloadOutcome.Ok)
            {
                return new TrailerStatusDto(key, TrailerStates.Failed);
            }
        }

        return new TrailerStatusDto(key, cache.Has(key) ? TrailerStates.Ready : TrailerStates.None);
    }

    /// <summary>Il file pronto e la lease che lo protegge dalla cancellazione finché si legge; null se la chiave non è risolta o il file non c'è.</summary>
    public (string Path, IDisposable Lease)? OpenStream(string key)
    {
        if (!resolver.WasResolved(key))
        {
            return null;
        }

        var lease = cache.OpenLease(key);
        if (!cache.Has(key))
        {
            lease.Dispose();
            return null;
        }

        return (cache.PathFor(key), lease);
    }

    /// <summary>Il download in corso o finito di questa chiave, per i test che lo aspettano.</summary>
    internal Task? Pending(string key) => _jobs.GetValueOrDefault(key);

    private async Task<TrailerDownloadOutcome> DownloadAsync(string id)
    {
        try
        {
            var outcome = await downloader.DownloadAsync(id, cache.PathFor(id), CancellationToken.None).ConfigureAwait(false);
            if (outcome == TrailerDownloadOutcome.Ok)
            {
                cache.Touch(id);
            }
            else
            {
                logger.LogWarning("Trailer {VideoId} non scaricato: {Outcome}", id, outcome);
            }

            return outcome;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Trailer {VideoId}: il download è fallito", id);
            return TrailerDownloadOutcome.Failed;
        }
    }
}
