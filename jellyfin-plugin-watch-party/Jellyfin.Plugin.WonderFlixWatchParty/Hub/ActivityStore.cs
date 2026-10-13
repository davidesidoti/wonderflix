using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// activity.json su disco (spec O §6.1, piano 21a decisione 1), accanto a
/// inbox.json nelle configurazioni dei plugin. Non è sicuro tra thread: lo
/// usa solo ActivityService, sotto lock.
/// </summary>
public sealed class ActivityStore(string filePath, ILogger<ActivityStore> logger)
{
    public const string FileName = "activity.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// activity.json.bad e si riparte vuoti; se non si riesce a spostarlo si
    /// riparte vuoti lo stesso (il prossimo salvataggio lo sovrascrive).
    /// </summary>
    public ActivityBook Load()
    {
        if (!File.Exists(FilePath))
        {
            return new ActivityBook();
        }

        try
        {
            var file = JsonSerializer.Deserialize<ActivityFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return ActivityBook.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Attività degli amici illeggibile: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                // Come i consigli: lo spostamento è una copia di cortesia. Nel log solo il percorso.
                logger.LogWarning(moveError, "Attività degli amici illeggibile e non spostabile in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return new ActivityBook();
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(ActivityBook book)
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
