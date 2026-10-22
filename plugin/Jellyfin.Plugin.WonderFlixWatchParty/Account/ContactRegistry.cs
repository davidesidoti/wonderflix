using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// I contatti di tutti gli utenti (spec L §7.2): in memoria, salvati con
/// <see cref="ContactStore"/> a ogni cambio. Un utente senza contatti e
/// senza promemoria esce dal file. Fuori di qui girano copie. Sicuro tra
/// thread.
/// </summary>
public sealed class ContactRegistry(ContactStore store, ILogger<ContactRegistry> logger)
{
    private readonly Lock _lock = new();
    private Dictionary<Guid, UserContacts>? _users;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private Dictionary<Guid, UserContacts> Users
    {
        get
        {
            if (_users is null)
            {
                _users = store.Load();
                logger.LogInformation("Contatti per il recupero in {Path}", store.FilePath);
            }

            return _users;
        }
    }

    /// <summary>Legge subito il file (all'avvio): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Users;
        }
    }

    /// <summary>I contatti dell'utente, come copia; vuoti se non ne ha.</summary>
    public UserContacts Get(Guid userId)
    {
        lock (_lock)
        {
            return Users.TryGetValue(userId, out var contacts) ? contacts.Copy() : new UserContacts();
        }
    }

    /// <summary>Tutti, come copie.</summary>
    public IReadOnlyDictionary<Guid, UserContacts> All()
    {
        lock (_lock)
        {
            return Users.ToDictionary(pair => pair.Key, pair => pair.Value.Copy());
        }
    }

    /// <summary>
    /// Salva il Discord dell'utente (una copia). ArgumentException se id o
    /// nome non sono validi: ContactStore rifiuta il file intero se una voce
    /// non è valida, quindi una voce sbagliata non deve mai entrarci.
    /// </summary>
    public void SetDiscord(Guid userId, DiscordContact contact)
    {
        if (!DiscordIds.IsSnowflake(contact.Id) || string.IsNullOrWhiteSpace(contact.Name))
        {
            throw new ArgumentException("Discord non valido", nameof(contact));
        }

        var copy = contact.Copy();
        Change(userId, contacts =>
        {
            contacts.Discord = copy;
            return true;
        });
    }

    /// <summary>
    /// Salva l'email dell'utente (una copia). ArgumentException se
    /// l'indirizzo è vuoto, per lo stesso motivo di <see cref="SetDiscord"/>.
    /// </summary>
    public void SetEmail(Guid userId, EmailContact contact)
    {
        if (string.IsNullOrWhiteSpace(contact.Address))
        {
            throw new ArgumentException("email non valida", nameof(contact));
        }

        var copy = contact.Copy();
        Change(userId, contacts =>
        {
            contacts.Email = copy;
            return true;
        });
    }

    /// <summary>Toglie il contatto di un canale; true se c'era.</summary>
    public bool Remove(Guid userId, AccountChannel channel) =>
        Change(userId, contacts =>
        {
            if (channel == AccountChannel.Discord)
            {
                var had = contacts.Discord is not null;
                contacts.Discord = null;
                return had;
            }

            var hadEmail = contacts.Email is not null;
            contacts.Email = null;
            return hadEmail;
        });

    /// <summary>Toglie tutti i contatti (resta l'ultimo promemoria); true se ce n'era almeno uno.</summary>
    public bool RemoveAll(Guid userId) =>
        Change(userId, contacts =>
        {
            var had = contacts.HasContact;
            contacts.Discord = null;
            contacts.Email = null;
            return had;
        });

    /// <summary>Segna l'ora dell'ultimo promemoria.</summary>
    public void MarkReminded(Guid userId, DateTimeOffset at) =>
        Change(userId, contacts =>
        {
            contacts.LastReminderAt = at;
            return true;
        });

    /// <summary>Toglie gli utenti che Jellyfin non ha più; restituisce quanti.</summary>
    public int Prune(Func<Guid, bool> userExists)
    {
        lock (_lock)
        {
            var gone = Users.Keys.Where(userId => !userExists(userId)).ToList();
            foreach (var userId in gone)
            {
                Users.Remove(userId);
            }

            if (gone.Count > 0)
            {
                Persist();
            }

            return gone.Count;
        }
    }

    private bool Change(Guid userId, Func<UserContacts, bool> change)
    {
        lock (_lock)
        {
            if (!Users.TryGetValue(userId, out var contacts))
            {
                contacts = new UserContacts();
                Users[userId] = contacts;
            }

            var changed = change(contacts);
            if (!contacts.HasContact && contacts.LastReminderAt is null)
            {
                Users.Remove(userId);
            }

            if (changed)
            {
                Persist();
            }

            return changed;
        }
    }

    // Solo sotto _lock. Un errore di disco non annulla il cambio in memoria:
    // finisce nel log e si riprova alla scrittura successiva.
    private void Persist()
    {
        try
        {
            store.Save(Users);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(ex, "Contatti non salvati in {Path}", store.FilePath);
        }
    }
}
