using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// friends.json su disco (spec F §6.1). Non sta nella cartella del plugin,
/// che cambia nome a ogni versione, ma nelle configurazioni dei plugin. Non
/// è sicuro tra thread: lo usa solo <see cref="FriendService"/>, sotto lock.
/// </summary>
public sealed class FriendStore(string filePath, ILogger<FriendStore> logger)
{
    /// <summary>Sottocartella dentro le configurazioni dei plugin.</summary>
    public const string FolderName = "WonderFlixWatchParty";

    public const string FileName = "friends.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// friends.json.bad e si riparte vuoti.
    /// </summary>
    public FriendGraph Load()
    {
        if (!File.Exists(FilePath))
        {
            return new FriendGraph();
        }

        try
        {
            var file = JsonSerializer.Deserialize<FriendFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return FriendGraph.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            File.Move(FilePath, bad, overwrite: true);
            logger.LogWarning(ex, "Amici illeggibili: file spostato in {Path}, si riparte vuoti", bad);
            return new FriendGraph();
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(FriendGraph graph)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, graph.ToFile(), Options);

            // Su disco prima della rinomina: senza, una caduta di corrente lascia friends.json vuoto.
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporary, FilePath, overwrite: true);
    }
}
