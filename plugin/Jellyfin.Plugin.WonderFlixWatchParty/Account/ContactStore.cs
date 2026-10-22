using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// contacts.json su disco (spec L §7.2), accanto a inbox.json nelle
/// configurazioni dei plugin. Non è sicuro tra thread: lo usa solo
/// ContactRegistry, sotto lock.
/// </summary>
public sealed class ContactStore(string filePath, ILogger<ContactStore> logger)
{
    public const string FileName = "contacts.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// contacts.json.bad e si riparte vuoti; se non si riesce a spostarlo si
    /// riparte vuoti lo stesso (il prossimo salvataggio lo sovrascrive).
    /// </summary>
    public Dictionary<Guid, UserContacts> Load()
    {
        if (!File.Exists(FilePath))
        {
            return [];
        }

        try
        {
            var file = JsonSerializer.Deserialize<ContactFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Contatti illeggibili: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                // Nel log solo il percorso, mai il contenuto (ci sono le email).
                logger.LogWarning(moveError, "Contatti illeggibili e non spostabili in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return [];
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(IReadOnlyDictionary<Guid, UserContacts> users)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, ToFile(users), Options);

            // Su disco prima della rinomina: senza, una caduta di corrente lascia il file vuoto.
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporary, FilePath, overwrite: true);
    }

    /// <summary>Dal file; FormatException se un utente o un contatto non è valido.</summary>
    internal static Dictionary<Guid, UserContacts> FromFile(ContactFile file)
    {
        var users = new Dictionary<Guid, UserContacts>();
        foreach (var (key, value) in file.Users ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || value is null)
            {
                throw new FormatException("contatti di un utente non validi");
            }

            if (value.Discord is { } discord && (!DiscordIds.IsSnowflake(discord.Id) || string.IsNullOrWhiteSpace(discord.Name)))
            {
                throw new FormatException("Discord non valido");
            }

            if (value.Email is { } email && string.IsNullOrWhiteSpace(email.Address))
            {
                throw new FormatException("email non valida");
            }

            users[userId] = value;
        }

        return users;
    }

    private static ContactFile ToFile(IReadOnlyDictionary<Guid, UserContacts> users) => new()
    {
        Users = users.ToDictionary(pair => pair.Key.ToString("N"), pair => (UserContacts?)pair.Value.Copy()),
    };
}
