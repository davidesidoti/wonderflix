using Jellyfin.Plugin.WonderFlixWatchParty.Space;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Conta le richieste di scansione della libreria.</summary>
internal sealed class FakeLibraryRefresh : ILibraryRefresh
{
    public int Calls { get; private set; }

    /// <summary>Chiamata a ogni richiesta: i test la usano per l'ordine delle chiamate.</summary>
    public Action? OnRefresh { get; set; }

    public void Refresh()
    {
        Calls++;
        OnRefresh?.Invoke();
    }
}
