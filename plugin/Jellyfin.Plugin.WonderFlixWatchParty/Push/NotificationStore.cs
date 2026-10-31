using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>
/// notifications.json su disco (spec V), accanto a inbox.json. Non è sicuro
/// tra thread: lo usa solo chi tiene il <see cref="NotificationBook"/>, sotto lock.
/// </summary>
public sealed class NotificationStore(string filePath, ILogger<NotificationStore> logger)
{
    public const string FileName = "notifications.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// notifications.json.bad e si riparte vuoti (se non si riesce a spostarlo
    /// si riparte vuoti lo stesso: il prossimo salvataggio lo sovrascrive).
    /// </summary>
    public NotificationBook Load()
    {
        if (!File.Exists(FilePath))
        {
            return new NotificationBook();
        }

        try
        {
            var file = JsonSerializer.Deserialize<NotificationFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return NotificationBook.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Iscrizioni push illeggibili: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                // Come InboxStore: lo spostamento è solo una cortesia. Nel log solo il percorso, mai il contenuto
                // (ci sono le chiavi delle iscrizioni).
                logger.LogWarning(moveError, "Iscrizioni push illeggibili e non spostabili in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return new NotificationBook();
        }
    }

    /// <summary>Scrive il file in modo atomico: file temporaneo nella stessa cartella, poi rinomina.</summary>
    public void Save(NotificationBook book)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, book.ToFile(), Options);
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporary, FilePath, overwrite: true);
    }
}
