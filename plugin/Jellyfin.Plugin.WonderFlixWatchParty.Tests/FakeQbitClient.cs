using Jellyfin.Plugin.WonderFlixWatchParty.Space;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>qBittorrent finto: torrent, file e tracker in dizionari (spec U §7.2).</summary>
internal sealed class FakeQbitClient : IQbitClient
{
    public List<QbitTorrent> Torrents { get; } = [];

    public Dictionary<string, List<QbitFile>> Files { get; } = [];

    public Dictionary<string, List<QbitTracker>> Trackers { get; } = [];

    /// <summary>Gli elenchi di hash passati a <see cref="DeleteAsync"/>, uno per chiamata.</summary>
    public List<IReadOnlyList<string>> Deleted { get; } = [];

    /// <summary>Se impostato, ogni chiamata fallisce con questo errore.</summary>
    public QbitError? Fail { get; set; }

    /// <summary>Chiamata a ogni cancellazione riuscita: i test la usano per l'ordine delle chiamate.</summary>
    public Action<IReadOnlyList<string>>? OnDelete { get; set; }

    public Task<IReadOnlyList<QbitTorrent>> GetTorrentsAsync(CancellationToken cancellationToken)
    {
        Check();
        return Task.FromResult<IReadOnlyList<QbitTorrent>>([.. Torrents]);
    }

    public Task<IReadOnlyList<QbitFile>> GetFilesAsync(string hash, CancellationToken cancellationToken)
    {
        Check();
        return Task.FromResult<IReadOnlyList<QbitFile>>(
            Files.TryGetValue(hash, out var files) ? [.. files] : throw new QbitException(QbitError.NotFound));
    }

    public Task<IReadOnlyList<QbitTracker>> GetTrackersAsync(string hash, CancellationToken cancellationToken)
    {
        Check();
        return Task.FromResult<IReadOnlyList<QbitTracker>>(
            Trackers.TryGetValue(hash, out var trackers) ? [.. trackers] : throw new QbitException(QbitError.NotFound));
    }

    public Task DeleteAsync(IReadOnlyList<string> hashes, CancellationToken cancellationToken)
    {
        Check();
        if (hashes.Count > 0)
        {
            Deleted.Add([.. hashes]);
            OnDelete?.Invoke(hashes);
        }

        return Task.CompletedTask;
    }

    private void Check()
    {
        if (Fail is { } error)
        {
            throw new QbitException(error);
        }
    }
}
