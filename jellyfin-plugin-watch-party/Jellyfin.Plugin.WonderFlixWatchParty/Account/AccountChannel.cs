namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>I canali dei codici (spec L §4).</summary>
public enum AccountChannel
{
    Discord,
    Email,
}

/// <summary>Nomi e lettura dei canali.</summary>
public static class AccountChannels
{
    /// <summary>Tutti, nell'ordine in cui si mandano i codici.</summary>
    public static readonly IReadOnlyList<AccountChannel> All = [AccountChannel.Discord, AccountChannel.Email];

    /// <summary>Il nome nelle rotte e nelle risposte: "Discord" o "Email".</summary>
    public static string Name(this AccountChannel channel) =>
        channel == AccountChannel.Discord ? "Discord" : "Email";

    /// <summary>Dal nome nella rotta, senza badare alle maiuscole. Niente numeri: "0" non è un canale.</summary>
    public static bool TryParse(string? raw, out AccountChannel channel)
    {
        foreach (var candidate in All)
        {
            if (string.Equals(raw, candidate.Name(), StringComparison.OrdinalIgnoreCase))
            {
                channel = candidate;
                return true;
            }
        }

        channel = default;
        return false;
    }
}
