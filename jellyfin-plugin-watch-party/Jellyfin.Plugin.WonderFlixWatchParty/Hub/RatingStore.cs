using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// ratings.json su disco (spec Q §6), accanto a inbox.json nelle
/// configurazioni dei plugin. Non è sicuro tra thread: lo usa solo
/// RatingService, sotto lock.
/// </summary>
public sealed class RatingStore(string filePath, ILogger<RatingStore> logger)
{
    public const string FileName = "ratings.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// ratings.json.bad e si riparte vuoti; se non si riesce a
    /// spostarlo si riparte vuoti lo stesso (il prossimo salvataggio lo
    /// sovrascrive).
    /// </summary>
    public RatingBook Load()
    {
        if (!File.Exists(FilePath))
        {
            return new RatingBook();
        }

        try
        {
            var file = JsonSerializer.Deserialize<RatingFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return RatingBook.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Voti illeggibili: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                // Come la cassetta: lo spostamento è una copia di cortesia, i voti
                // devono funzionare lo stesso. Nel log solo il percorso, mai il contenuto.
                logger.LogWarning(moveError, "Voti illeggibili e non spostabili in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return new RatingBook();
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(RatingBook book)
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
