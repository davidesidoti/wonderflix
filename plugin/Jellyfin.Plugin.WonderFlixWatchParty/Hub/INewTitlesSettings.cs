namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>La casella "Notify new titles" della Dashboard (spec G §6.8).</summary>
public interface INewTitlesSettings
{
    /// <summary>Il valore di adesso: va letto ogni volta.</summary>
    bool NotifyNewTitles { get; }
}
