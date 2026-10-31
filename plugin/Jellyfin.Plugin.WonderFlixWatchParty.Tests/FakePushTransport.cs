using Jellyfin.Plugin.WonderFlixWatchParty.Push;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Un invio visto da <see cref="FakePushTransport"/>.</summary>
internal sealed record SentPush(PushSubscription Sub, byte[] Body, string Authorization);

/// <summary>Registra gli invii e risponde con <see cref="Result"/> (per endpoint con <see cref="ResultFor"/>).</summary>
internal sealed class FakePushTransport : IPushTransport
{
    public List<SentPush> Sent { get; } = [];

    public PushResult Result { get; set; } = PushResult.Sent;

    public Dictionary<string, PushResult> ResultFor { get; } = [];

    public Task<PushResult> SendAsync(PushSubscription sub, byte[] body, string authorization, CancellationToken ct)
    {
        Sent.Add(new SentPush(sub, body, authorization));
        return Task.FromResult(ResultFor.TryGetValue(sub.Endpoint, out var result) ? result : Result);
    }
}
