namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Le impostazioni della pagina Spazio, lette a ogni uso (spec U §7.1).</summary>
public interface ISpaceSettings
{
    /// <summary>Indirizzo di qBittorrent; vuoto se non è configurato.</summary>
    string QbitUrl { get; }

    /// <summary>Utente di qBittorrent.</summary>
    string QbitUser { get; }

    /// <summary>Password di qBittorrent: non torna mai nelle risposte né nel registro.</summary>
    string QbitPassword { get; }

    /// <summary>Mesi senza che nessuno apra un titolo perché sia fermo.</summary>
    int StaleMonths { get; }

    /// <summary>Giorni in cui una richiesta recente protegge un titolo.</summary>
    int RequestGraceDays { get; }

    /// <summary>Voto medio sotto il quale un titolo è poco gradito.</summary>
    int LowRating { get; }

    /// <summary>Voto medio da cui un titolo si tiene.</summary>
    int HighRating { get; }

    /// <summary>Voti minimi perché la media conti.</summary>
    int MinRatings { get; }

    /// <summary>GB all'ora oltre i quali un file è "pesante" (alleggerire).</summary>
    double HeavyGbPerHour { get; }

    /// <summary>La regola del seed obbligatorio.</summary>
    SeedSettings Seed { get; }

    /// <summary>Le cartelle dove si cercano i file orfani; il plugin cancella solo lì dentro.</summary>
    IReadOnlyList<string> ScanFolders { get; }

    /// <summary>Percorso del file con la quota; vuoto se non è configurato.</summary>
    string QuotaFile { get; }
}
