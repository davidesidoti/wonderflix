using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>Un dispositivo iscritto alle push (spec V). Lo stesso endpoint con due utenti sono due iscrizioni.</summary>
public sealed class PushSubscription
{
    public Guid UserId { get; set; }

    /// <summary>L'URL https del servizio push: identifica il browser, nel log va solo l'host.</summary>
    public string Endpoint { get; set; } = string.Empty;

    public string P256dh { get; set; } = string.Empty;

    public string Auth { get; set; } = string.Empty;

    /// <summary>Il dispositivo Jellyfin della sessione che ha iscritto: se la sessione sparisce, l'iscrizione va tolta.</summary>
    public string DeviceId { get; set; } = string.Empty;

    /// <summary>"it" o "en".</summary>
    public string Language { get; set; } = "en";

    public DateTimeOffset CreatedAt { get; set; }
}

/// <summary>
/// Contenuto di notifications.json. Tutto nullable: un file scritto a mano o
/// rovinato si scopre in <see cref="NotificationBook.FromFile"/>.
/// </summary>
public sealed class NotificationFile
{
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Subscriptions")]
    public List<PushSubscription?>? Subscriptions { get; set; } = [];

    /// <summary>Per utente (formato "N") i tipi spenti: di default tutto è acceso.</summary>
    [JsonPropertyName("Disabled")]
    public Dictionary<string, List<string>?>? Disabled { get; set; } = [];
}

/// <summary>
/// Iscrizioni push e preferenze per tipo, in memoria (spec V). Non è sicuro
/// tra thread: lo usa solo chi lo tiene, sotto lock.
/// </summary>
public sealed class NotificationBook
{
    private readonly List<PushSubscription> _subscriptions = [];
    private readonly Dictionary<Guid, HashSet<string>> _disabled = [];

    /// <summary>Aggiunge l'iscrizione, o sostituisce quella con lo stesso utente e lo stesso endpoint.</summary>
    public void Upsert(PushSubscription subscription)
    {
        _subscriptions.RemoveAll(s => Same(s, subscription.UserId, subscription.Endpoint));
        _subscriptions.Add(subscription);
    }

    public bool Remove(Guid userId, string endpoint) =>
        _subscriptions.RemoveAll(s => Same(s, userId, endpoint)) > 0;

    /// <summary>Toglie proprio quella riga (letta prima con <see cref="For"/>); false se intanto è stata sostituita.</summary>
    public bool Remove(PushSubscription subscription) => _subscriptions.Remove(subscription);

    /// <summary>Toglie l'endpoint per tutti gli utenti (il servizio push dice che non esiste più).</summary>
    public bool RemoveEndpoint(string endpoint) =>
        _subscriptions.RemoveAll(s => s.Endpoint == endpoint) > 0;

    public IReadOnlyList<PushSubscription> For(Guid userId) =>
        _subscriptions.Where(s => s.UserId == userId).ToList();

    public bool IsEnabled(Guid userId, string type) =>
        !(_disabled.TryGetValue(userId, out var off) && off.Contains(type));

    /// <summary>Accende o spegne un tipo; true se è cambiato qualcosa.</summary>
    public bool SetEnabled(Guid userId, string type, bool enabled)
    {
        if (enabled)
        {
            if (!_disabled.TryGetValue(userId, out var off) || !off.Remove(type))
            {
                return false;
            }

            if (off.Count == 0)
            {
                _disabled.Remove(userId);
            }

            return true;
        }

        if (!_disabled.TryGetValue(userId, out var set))
        {
            _disabled[userId] = set = [];
        }

        return set.Add(type);
    }

    /// <summary>Toglie iscrizioni e preferenze degli utenti che non esistono più; restituisce le iscrizioni tolte.</summary>
    public int Prune(Func<Guid, bool> userExists)
    {
        foreach (var user in _disabled.Keys.Where(u => !userExists(u)).ToList())
        {
            _disabled.Remove(user);
        }

        var gone = _subscriptions.Select(s => s.UserId).Distinct().Where(u => !userExists(u)).ToHashSet();
        return _subscriptions.RemoveAll(s => gone.Contains(s.UserId));
    }

    public static NotificationBook FromFile(NotificationFile file)
    {
        var book = new NotificationBook();
        foreach (var subscription in file.Subscriptions ?? [])
        {
            if (subscription is null || subscription.UserId == Guid.Empty || string.IsNullOrEmpty(subscription.Endpoint))
            {
                throw new FormatException("iscrizione non valida");
            }

            book.Upsert(subscription);
        }

        foreach (var (key, types) in file.Disabled ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || types is null)
            {
                throw new FormatException("preferenze di un utente non valide");
            }

            book._disabled[userId] = types.ToHashSet();
        }

        return book;
    }

    public NotificationFile ToFile() => new()
    {
        Subscriptions = _subscriptions.Select(s => (PushSubscription?)s).ToList(),
        Disabled = _disabled.ToDictionary(p => p.Key.ToString("N"), p => (List<string>?)p.Value.Order().ToList()),
    };

    private static bool Same(PushSubscription s, Guid userId, string endpoint) =>
        s.UserId == userId && s.Endpoint == endpoint;
}
