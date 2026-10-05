using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Collegamento a Seerr fisso, da cambiare nel test.</summary>
internal sealed class FakeSeerrSettings : ISeerrSettings
{
    public string Url { get; set; } = "https://seerr.example";

    public string ApiKey { get; set; } = "key";

    public string WebhookSecret { get; set; } = "secret";
}
