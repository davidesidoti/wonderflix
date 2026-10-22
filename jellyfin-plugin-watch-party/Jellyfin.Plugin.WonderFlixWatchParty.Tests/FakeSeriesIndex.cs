using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Serie della libreria in memoria; Fails la fa lanciare, come un errore di Jellyfin.</summary>
internal sealed class FakeSeriesIndex : ISeriesIndex
{
    public List<LibrarySeries> Series { get; } = [];

    public List<LibraryMovie> Movies { get; } = [];

    public bool Fails { get; set; }

    public IReadOnlyList<LibrarySeries> GetSeries() =>
        Fails ? throw new InvalidOperationException("libreria non disponibile") : Series.ToList();

    public IReadOnlyList<LibraryMovie> GetMovies() =>
        Fails ? throw new InvalidOperationException("libreria non disponibile") : Movies.ToList();
}
