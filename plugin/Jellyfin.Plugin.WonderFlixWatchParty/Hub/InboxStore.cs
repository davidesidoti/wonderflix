using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// inbox.json su disco (spec G §6.1), accanto a friends.json nelle
/// configurazioni dei plugin. Non è sicuro tra thread: lo usa solo
/// InboxService, sotto lock.
/// </summary>
public sealed class InboxStore(string filePath, ILogger<InboxStore> logger)
{
    public const string FileName = "inbox.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// inbox.json.bad e si riparte vuoti; se non si riesce a spostarlo si
    /// riparte vuoti lo stesso (il prossimo salvataggio lo sovrascrive).
    /// </summary>
    public InboxBook Load()
    {
        if (!File.Exists(FilePath))
        {
            return new InboxBook();
        }

        try
        {
            var file = JsonSerializer.Deserialize<InboxFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return InboxBook.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Cassetta delle notifiche illeggibile: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                // Lo spostamento è solo una copia di cortesia: se fallisce la cassetta deve
                // comunque funzionare. Il file illeggibile resta dov'è e il prossimo
                // salvataggio lo sovrascrive. Nel log solo il percorso, mai il contenuto.
                logger.LogWarning(moveError, "Cassetta delle notifiche illeggibile e non spostabile in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return new InboxBook();
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(InboxBook book)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, book.ToFile(), Options);

            // Su disco prima della rinomina: senza, una caduta di corrente lascia inbox.json vuoto.
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporary, FilePath, overwrite: true);
    }
}
