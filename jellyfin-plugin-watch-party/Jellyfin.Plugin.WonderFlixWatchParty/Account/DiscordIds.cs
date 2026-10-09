namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Gli id di Discord (snowflake): da 17 a 20 cifre. Vanno nei percorsi dell'API.</summary>
public static class DiscordIds
{
    public static bool IsSnowflake(string? value) =>
        value is { Length: >= 17 and <= 20 } && value.All(char.IsAsciiDigit);
}
