namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>Esito di un invio: Gone = il servizio push non conosce più l'iscrizione, va tolta.</summary>
public enum PushResult
{
    Sent,
    Gone,
    Failed,
}

/// <summary>Spedisce al servizio push del browser un corpo già cifrato.</summary>
public interface IPushTransport
{
    Task<PushResult> SendAsync(PushSubscription sub, byte[] body, string authorization, CancellationToken ct);
}
