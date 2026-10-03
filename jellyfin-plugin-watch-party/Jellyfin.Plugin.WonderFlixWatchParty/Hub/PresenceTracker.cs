using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Avvisa gli amici quando un utente va online o offline (spec F §6.3). I
/// cambi ravvicinati (riconnessioni, più dispositivi) diventano un solo
/// avviso, <see cref="Delay"/> dopo il primo: intanto le sessioni di
/// Jellyfin si sono assestate. Sicuro tra thread.
/// </summary>
public sealed class PresenceTracker(FriendService friends, TimeProvider time, ILogger<PresenceTracker> logger) : IDisposable
{
    /// <summary>Attesa tra il primo cambio e l'avviso agli amici.</summary>
    public static readonly TimeSpan Delay = TimeSpan.FromSeconds(2);

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, ITimer> _pending = [];

    /// <summary>Lo stato online di userId può essere cambiato.</summary>
    public void Changed(Guid userId)
    {
        lock (_lock)
        {
            if (_pending.ContainsKey(userId))
            {
                return;
            }

            _pending[userId] = time.CreateTimer(_ => Fire(userId), null, Delay, Timeout.InfiniteTimeSpan);
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            foreach (var timer in _pending.Values)
            {
                timer.Dispose();
            }

            _pending.Clear();
        }
    }

    private void Fire(Guid userId)
    {
        lock (_lock)
        {
            if (_pending.Remove(userId, out var timer))
            {
                timer.Dispose();
            }
        }

        _ = NotifyAsync(userId);
    }

    private async Task NotifyAsync(Guid userId)
    {
        try
        {
            await friends.NotifyFriendsAsync(userId).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Presenza di {UserId} non comunicata agli amici", userId);
        }
    }
}
