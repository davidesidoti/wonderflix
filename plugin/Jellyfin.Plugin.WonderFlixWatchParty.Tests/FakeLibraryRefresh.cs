using Jellyfin.Plugin.WonderFlixWatchParty.Space;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Conta le richieste di scansione della libreria.</summary>
internal sealed class FakeLibraryRefresh : ILibraryRefresh
{
    public int Calls { get; private set; }

    public void Refresh() => Calls++;
}
