namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Cartella temporanea per un test, cancellata alla fine.</summary>
internal sealed class TempFolder : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "wfwp-" + Guid.NewGuid().ToString("N"));

    /// <summary>Percorso di friends.json in una sottocartella non ancora creata.</summary>
    public string FriendsFile => System.IO.Path.Combine(Path, "WonderFlixWatchParty", "friends.json");

    public void Dispose()
    {
        if (Directory.Exists(Path))
        {
            Directory.Delete(Path, recursive: true);
        }
    }
}
