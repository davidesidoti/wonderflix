using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Libreria dei trailer finta: un solo elemento, o nessuno.</summary>
internal sealed class FakeTrailerLibrary : ITrailerLibrary
{
    public TrailerItem? Item { get; set; }

    public TrailerItem? Find(Guid userId, Guid itemId) => Item;
}
