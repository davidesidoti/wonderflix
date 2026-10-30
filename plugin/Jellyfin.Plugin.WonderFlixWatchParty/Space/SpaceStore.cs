using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>
/// space.json su disco (spec U §7.3), accanto a downloads.json. Non è sicuro tra
/// thread: lo usa solo <see cref="SpaceService"/>, sotto lock.
/// </summary>
public sealed class SpaceStore(string filePath, ILogger<SpaceStore> logger)
{
    public const string FileName = "space.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile o di una versione diversa
    /// va in space.json.bad e si riparte vuoti; se non si riesce a spostarlo si riparte
    /// vuoti lo stesso (il prossimo salvataggio lo sovrascrive).
    /// </summary>
    public SpaceBook Load()
    {
        if (!File.Exists(FilePath))
        {
            return new SpaceBook();
        }

        try
        {
            var file = JsonSerializer.Deserialize<SpaceFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return SpaceBook.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Spazio illeggibile: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                logger.LogWarning(moveError, "Spazio illeggibile e non spostabile in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return new SpaceBook();
        }
    }

    /// <summary>Scrive il file in modo atomico: un file temporaneo nella stessa cartella, poi la rinomina.</summary>
    public void Save(SpaceBook book)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, book.ToFile(), Options);

            // Su disco prima della rinomina: senza, una caduta di corrente lascia il file vuoto.
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporary, FilePath, overwrite: true);
    }
}
