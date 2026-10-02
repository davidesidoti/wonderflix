using Jellyfin.Plugin.WonderFlixWatchParty.Hub;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Server finto: sessioni, gruppi SyncPlay e invii, in memoria.</summary>
internal sealed class FakeServer : ISessionDirectory, IGroupDirectory, IEventSender
{
    public List<CallerSession> Sessions { get; } = [];

    /// <summary>Gruppo → nomi utente dei partecipanti.</summary>
    public Dictionary<Guid, List<string>> Groups { get; } = [];

    public List<(string SessionId, string Payload)> Sent { get; } = [];

    /// <summary>Sessioni per cui l'invio lancia un errore.</summary>
    public HashSet<string> Failing { get; } = [];

    public CallerSession AddSession(string sessionId, string userName)
    {
        var session = new CallerSession(sessionId, Guid.NewGuid(), userName);
        Sessions.Add(session);
        return session;
    }

    // Nei test il dispositivo di una sessione ha lo stesso id della sessione.
    public CallerSession? FindCaller(string? deviceId, string? client, Guid userId) =>
        Sessions.FirstOrDefault(s => s.SessionId == deviceId && s.UserId == userId);

    public bool Exists(string sessionId) => Sessions.Any(s => s.SessionId == sessionId);

    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId) =>
        Exists(sessionId) && Groups.TryGetValue(groupId, out var participants) ? participants : null;

    public Task<bool> TrySendAsync(string sessionId, string payload, CancellationToken cancellationToken)
    {
        if (Failing.Contains(sessionId))
        {
            throw new InvalidOperationException("invio fallito");
        }

        if (!Exists(sessionId))
        {
            return Task.FromResult(false);
        }

        Sent.Add((sessionId, payload));
        return Task.FromResult(true);
    }
}
