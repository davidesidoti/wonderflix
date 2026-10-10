namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>La Home dell'admin (spec M §6.2), salvata nella configurazione del plugin.</summary>
public interface IHomeLayoutStore
{
    /// <summary>Gli id delle righe accese, in ordine; null se mai impostata (vale l'ordine predefinito dell'app).</summary>
    IReadOnlyList<string>? Rows { get; }

    /// <summary>Salva la Home dell'admin; null torna all'ordine predefinito.</summary>
    void Save(IReadOnlyList<string>? rows);
}
