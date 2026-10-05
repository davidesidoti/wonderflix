using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>
/// Utente Jellyfin → utente Seerr, per jellyfinUserId (spec I §7.2): con più
/// account per lo stesso utente vince l'id Seerr più basso. Utenti e
/// permessi predefiniti restano in memoria per <see cref="CacheFor"/>.
/// Sicuro tra thread.
/// </summary>
public sealed class SeerrUserMap(ISeerrClient seerr, TimeProvider time, ILogger<SeerrUserMap> logger)
{
    /// <summary>Quanto valgono gli utenti e i permessi predefiniti letti da Seerr.</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromMinutes(10);

    private readonly SemaphoreSlim _gate = new(1, 1);
    private Snapshot<IReadOnlyList<SeerrUser>>? _users;
    private Snapshot<int>? _defaultPermissions;

    /// <summary>L'utente Seerr dell'utente Jellyfin; null se non ha un account.</summary>
    public async Task<SeerrUser?> FindAsync(Guid jellyfinUserId, CancellationToken cancellationToken) =>
        Match(await UsersAsync(cancellationToken).ConfigureAwait(false), jellyfinUserId);

    /// <summary>
    /// L'utente Seerr, creato con l'import da Jellyfin se manca (spec I
    /// §7.2). AccountUnavailable se l'import non lo crea; Unavailable e
    /// NotConfigured passano come sono.
    /// </summary>
    public async Task<SeerrUser> EnsureAsync(Guid jellyfinUserId, CancellationToken cancellationToken)
    {
        var user = await FindAsync(jellyfinUserId, cancellationToken).ConfigureAwait(false);
        if (user is not null)
        {
            return user;
        }

        try
        {
            await seerr.ImportJellyfinUserAsync(jellyfinUserId, cancellationToken).ConfigureAwait(false);
        }
        catch (SeerrException ex) when (ex.Error is not (SeerrError.Unavailable or SeerrError.NotConfigured))
        {
            logger.LogWarning("Account Seerr non creato per l'utente {UserId}: {Error}", jellyfinUserId, ex.Error);
            throw new SeerrException(SeerrError.AccountUnavailable, ex);
        }

        Invalidate();
        user = await FindAsync(jellyfinUserId, cancellationToken).ConfigureAwait(false);
        if (user is null)
        {
            logger.LogWarning("Import in Seerr senza account per l'utente {UserId}", jellyfinUserId);
            throw new SeerrException(SeerrError.AccountUnavailable);
        }

        logger.LogInformation("Account Seerr {SeerrId} creato per l'utente {UserId}", user.Id, jellyfinUserId);
        return user;
    }

    /// <summary>Gli id Jellyfin di chi può approvare: account Seerr con ADMIN o MANAGE_REQUESTS.</summary>
    public async Task<IReadOnlyList<Guid>> ManagerJellyfinIdsAsync(CancellationToken cancellationToken) =>
        (await UsersAsync(cancellationToken).ConfigureAwait(false))
            .Where(u => SeerrPermissions.CanManage(u.Permissions))
            .Select(u => SeerrMapping.ParseGuid(u.JellyfinUserId))
            .OfType<Guid>()
            .Distinct()
            .ToList();

    /// <summary>I permessi che Seerr dà ai nuovi account (spec I §7.3, GET Me senza account).</summary>
    public Task<int> DefaultPermissionsAsync(CancellationToken cancellationToken) =>
        CachedAsync(
            () => _defaultPermissions,
            fresh => _defaultPermissions = fresh,
            async ct => (await seerr.GetMainSettingsAsync(ct).ConfigureAwait(false)).DefaultPermissions,
            cancellationToken);

    /// <summary>La prossima lettura chiede di nuovo gli utenti a Seerr (dopo un import).</summary>
    public void Invalidate() => _users = null;

    internal static SeerrUser? Match(IEnumerable<SeerrUser> users, Guid jellyfinUserId) =>
        users.Where(u => SeerrMapping.ParseGuid(u.JellyfinUserId) == jellyfinUserId).MinBy(u => u.Id);

    private Task<IReadOnlyList<SeerrUser>> UsersAsync(CancellationToken cancellationToken) =>
        CachedAsync(() => _users, fresh => _users = fresh, seerr.GetUsersAsync, cancellationToken);

    // Una lettura sola alla volta: chi arriva mentre un'altra è in corso
    // aspetta e usa il suo risultato.
    private async Task<T> CachedAsync<T>(
        Func<Snapshot<T>?> read,
        Action<Snapshot<T>> write,
        Func<CancellationToken, Task<T>> load,
        CancellationToken cancellationToken)
    {
        if (Fresh(read()) is { } hit)
        {
            return hit.Value;
        }

        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (Fresh(read()) is { } again)
            {
                return again.Value;
            }

            var value = await load(cancellationToken).ConfigureAwait(false);
            write(new Snapshot<T>(value, time.GetUtcNow()));
            return value;
        }
        finally
        {
            _gate.Release();
        }
    }

    private Snapshot<T>? Fresh<T>(Snapshot<T>? snapshot) =>
        snapshot is not null && time.GetUtcNow() - snapshot.LoadedAt < CacheFor ? snapshot : null;

    private sealed record Snapshot<T>(T Value, DateTimeOffset LoadedAt);
}
