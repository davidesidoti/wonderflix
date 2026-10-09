using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il modulo Account dei test: server finto, canali finti, file in una cartella temporanea.</summary>
internal sealed class AccountRig : IDisposable
{
    public AccountRig()
    {
        Contacts = TestAccount.Registry(Folder);
        Codes = new CodeBook(Time);
        Limiter = new RateLimiter(Time);
        Inbox = TestInbox.Create(Server, Folder, Time);
        Sender = new AccountSender(Discord, Mail, Settings, Time);
    }

    public TempFolder Folder { get; } = new();

    public FakeServer Server { get; } = new();

    public FakeTimeProvider Time { get; } = new(new DateTimeOffset(2026, 10, 9, 12, 0, 0, TimeSpan.Zero));

    public FakeAccountSettings Settings { get; } = new();

    public FakeDiscordSender Discord { get; } = new();

    public FakeMailSender Mail { get; } = new();

    /// <summary>Il cambio di password finto del recupero (non il controllo della password attuale: quello è <see cref="PasswordCheck"/>).</summary>
    public FakePasswordReset Passwords { get; } = new();

    public FakePasswordCheck PasswordCheck { get; } = new();

    public ContactRegistry Contacts { get; }

    public CodeBook Codes { get; }

    public RateLimiter Limiter { get; }

    public InboxService Inbox { get; }

    public AccountSender Sender { get; }

    /// <summary>
    /// Un utente con Discord ed email già verificati: l'id Discord è un
    /// numero di 18 cifre, il nome Discord e l'email sono il nome in minuscolo.
    /// </summary>
    public UserRef UserWithContacts(string name, bool isAdmin = false, bool enabled = true)
    {
        var user = Server.AddUser(name, enabled, isAdmin: isAdmin);
        var lower = name.ToLowerInvariant();
        var discordId = (100_000_000_000_000_000L + Server.Users.Count).ToString(CultureInfo.InvariantCulture);
        Contacts.SetDiscord(user.Id, new DiscordContact { Id = discordId, Name = lower, VerifiedAt = Time.GetUtcNow() });
        Contacts.SetEmail(user.Id, new EmailContact { Address = lower + "@example.com", VerifiedAt = Time.GetUtcNow() });
        return user;
    }

    public ContactLinking Linking() =>
        new(Contacts, Codes, Limiter, Discord, PasswordCheck, Sender, Settings, Inbox, Time, NullLogger<ContactLinking>.Instance);

    public PasswordRecovery Recovery() =>
        new(Server, Contacts, Codes, Limiter, Sender, Passwords, NullLogger<PasswordRecovery>.Instance);

    public AccountAdmin Admin() => new(Server, Contacts, Sender, Discord, Settings);

    public ContactReminders Reminders() =>
        new(Server, Contacts, Inbox, Settings, Time, NullLogger<ContactReminders>.Instance);

    public void Dispose() => Folder.Dispose();
}
